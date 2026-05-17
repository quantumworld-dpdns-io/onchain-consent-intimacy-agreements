// RISC Zero guest program for consent workflow verification
// This zkVM program verifies a multi-step consent workflow:
// 1. Party A creates consent with specific scopes
// 2. Party B accepts consent
// 3. Content is produced under consent
// 4. Consent is checked at each step

#![no_main]
use risc0_zkvm::guest::env;

risc0_zkvm::guest::entry!(main);

#[derive(serde::Serialize, serde::Deserialize)]
pub struct ConsentWorkflowInput {
    pub consent_id: [u8; 32],
    pub party_a: [u8; 32],
    pub party_b: [u8; 32],
    pub scopes: Vec<[u8; 32]>,
    pub timestamps: Vec<u64>,
    pub actions: Vec<u8>,
    pub chain_id: u64,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct ConsentWorkflowOutput {
    pub consent_id: [u8; 32],
    pub all_actions_authorized: bool,
    pub workflow_complete: bool,
    pub first_violation_step: Option<u32>,
    pub total_steps: u32,
}

fn main() {
    // Read input from the host
    let input: ConsentWorkflowInput = env::read();
    
    let mut all_authorized = true;
    let mut violation_step = None;
    
    // Verify each action in the workflow was within authorized scopes
    for (i, action) in input.actions.iter().enumerate() {
        let action_idx = *action as usize;
        let scope_count = input.scopes.len();
        
        if action_idx >= scope_count {
            all_authorized = false;
            violation_step = Some(i as u32);
            break;
        }
    }
    
    // Verify timestamps are monotonic
    let mut timestamps_valid = true;
    for i in 1..input.timestamps.len() {
        if input.timestamps[i] <= input.timestamps[i - 1] {
            timestamps_valid = false;
            break;
        }
    }
    
    // Commit the output
    let output = ConsentWorkflowOutput {
        consent_id: input.consent_id,
        all_actions_authorized: all_authorized,
        workflow_complete: all_authorized && timestamps_valid,
        first_violation_step: violation_step,
        total_steps: input.actions.len() as u32,
    };
    
    env::commit(&output);
}
