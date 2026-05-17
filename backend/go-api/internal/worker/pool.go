package worker

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/rs/zerolog"
)

type TaskType int

const (
	TaskProofGeneration TaskType = iota
	TaskQdrantIndexing
	TaskNotificationDispatch
	TaskEventIndexing
)

func (t TaskType) String() string {
	switch t {
	case TaskProofGeneration:
		return "proof_generation"
	case TaskQdrantIndexing:
		return "qdrant_indexing"
	case TaskNotificationDispatch:
		return "notification_dispatch"
	case TaskEventIndexing:
		return "event_indexing"
	default:
		return "unknown"
	}
}

type TaskStatus int

const (
	TaskPending TaskStatus = iota
	TaskRunning
	TaskCompleted
	TaskFailed
	TaskRetry
)

type Task struct {
	ID        string
	Type      TaskType
	Data      interface{}
	Status    TaskStatus
	Error     error
	Retries   int
	MaxRetries int
	CreatedAt time.Time
	UpdatedAt time.Time
}

type Pool struct {
	ctx       context.Context
	cancel    context.CancelFunc
	tasks     chan *Task
	retry     chan *Task
	done      chan struct{}
	wg        sync.WaitGroup
	handlers  map[TaskType]TaskHandler
	logger    *zerolog.Logger
	active    int32
	queued    int32
	completed int32
	failed    int32
}

type TaskHandler func(context.Context, *Task) error

func NewPool(ctx context.Context, numWorkers int, queueSize int, logger *zerolog.Logger) *Pool {
	ctx, cancel := context.WithCancel(ctx)

	p := &Pool{
		ctx:      ctx,
		cancel:   cancel,
		tasks:    make(chan *Task, queueSize),
		retry:    make(chan *Task, queueSize),
		done:     make(chan struct{}),
		handlers: make(map[TaskType]TaskHandler),
		logger:   logger,
	}

	for i := 0; i < numWorkers; i++ {
		p.wg.Add(1)
		go p.worker(i)
	}

	go p.retryLoop()

	logger.Info().Int("workers", numWorkers).Int("queue_size", queueSize).Msg("worker pool started")
	return p
}

func (p *Pool) RegisterHandler(taskType TaskType, handler TaskHandler) {
	p.handlers[taskType] = handler
}

func (p *Pool) Submit(task *Task) error {
	select {
	case p.tasks <- task:
		atomic.AddInt32(&p.queued, 1)
		return nil
	case <-p.ctx.Done():
		return fmt.Errorf("pool is shutting down")
	default:
		return fmt.Errorf("task queue is full")
	}
}

func (p *Pool) SubmitWithRetry(task *Task, maxRetries int) error {
	task.MaxRetries = maxRetries
	return p.Submit(task)
}

func (p *Pool) worker(id int) {
	defer p.wg.Done()

	p.logger.Debug().Int("worker_id", id).Msg("worker started")

	for {
		select {
		case task := <-p.tasks:
			p.processTask(id, task)
		case task := <-p.retry:
			p.processTask(id, task)
		case <-p.ctx.Done():
			p.logger.Debug().Int("worker_id", id).Msg("worker stopping")
			return
		}
	}
}

func (p *Pool) processTask(workerID int, task *Task) {
	atomic.AddInt32(&p.active, 1)
	defer atomic.AddInt32(&p.active, -1)

	task.Status = TaskRunning
	task.UpdatedAt = time.Now()

	handler, ok := p.handlers[task.Type]
	if !ok {
		task.Status = TaskFailed
		task.Error = fmt.Errorf("no handler registered for task type %s", task.Type)
		atomic.AddInt32(&p.failed, 1)
		p.logger.Error().
			Int("worker_id", workerID).
			Str("task_id", task.ID).
			Str("task_type", task.Type.String()).
			Err(task.Error).
			Msg("no handler for task")
		return
	}

	p.logger.Debug().
		Int("worker_id", workerID).
		Str("task_id", task.ID).
		Str("task_type", task.Type.String()).
		Msg("processing task")

	if err := handler(p.ctx, task); err != nil {
		task.Retries++
		if task.Retries <= task.MaxRetries {
			task.Status = TaskRetry
			task.Error = err
			task.UpdatedAt = time.Now()

			backoff := time.Duration(1<<uint(task.Retries-1)) * time.Second
			if backoff > 30*time.Second {
				backoff = 30 * time.Second
			}

			p.logger.Warn().
				Int("worker_id", workerID).
				Str("task_id", task.ID).
				Str("task_type", task.Type.String()).
				Int("retry", task.Retries).
				Dur("backoff", backoff).
				Err(err).
				Msg("task failed, scheduling retry")

			time.AfterFunc(backoff, func() {
				select {
				case p.retry <- task:
				case <-p.ctx.Done():
				}
			})
			return
		}

		task.Status = TaskFailed
		task.Error = err
		atomic.AddInt32(&p.failed, 1)

		p.logger.Error().
			Int("worker_id", workerID).
			Str("task_id", task.ID).
			Str("task_type", task.Type.String()).
			Int("retries", task.Retries).
			Err(err).
			Msg("task failed permanently")
		return
	}

	task.Status = TaskCompleted
	task.UpdatedAt = time.Now()
	atomic.AddInt32(&p.completed, 1)

	p.logger.Info().
		Int("worker_id", workerID).
		Str("task_id", task.ID).
		Str("task_type", task.Type.String()).
		Msg("task completed successfully")
}

func (p *Pool) retryLoop() {
	<-p.ctx.Done()
}

func (p *Pool) Shutdown() {
	p.logger.Info().Msg("shutting down worker pool")
	p.cancel()
	p.wg.Wait()
	close(p.done)
	p.logger.Info().Msg("worker pool shut down")
}

func (p *Pool) Stats() PoolStats {
	return PoolStats{
		Active:    atomic.LoadInt32(&p.active),
		Queued:    atomic.LoadInt32(&p.queued),
		Completed: atomic.LoadInt32(&p.completed),
		Failed:    atomic.LoadInt32(&p.failed),
	}
}

type PoolStats struct {
	Active    int32
	Queued    int32
	Completed int32
	Failed    int32
}
