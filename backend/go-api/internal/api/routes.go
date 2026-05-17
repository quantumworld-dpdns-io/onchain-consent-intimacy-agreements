package api

import (
	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"
)

func RegisterRoutes(r *gin.Engine, handler *Handler, logger *zerolog.Logger) {
	rl := NewRateLimiter(100, 200)

	r.Use(CORSMiddleware())
	r.Use(RequestLogger(logger))
	r.Use(RateLimitMiddleware(rl))

	api := r.Group("/api/v1")
	api.Use(AuthMiddleware(handler.cfg, handler.logger))

	api.POST("/consent", handler.CreateConsent)
	api.GET("/consent/:id", handler.GetConsent)
	api.POST("/consent/:id/verify", handler.VerifyConsent)
	api.POST("/consent/:id/revoke", handler.RevokeConsent)
	api.POST("/consent/:id/proof", handler.GenerateProof)

	api.GET("/parties/:addr/consents", handler.GetPartyConsents)

	api.GET("/search", handler.SearchConsents)

	api.GET("/chains", handler.GetChains)
	api.GET("/chains/:chain/status", ChainMiddleware(), handler.GetChainStatus)

	logger.Info().Msg("routes registered")
}
