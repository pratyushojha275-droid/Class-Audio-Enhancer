%% ============================================================
% 5. STAGE C: POLISH PASS (removes what the neural stage leaves behind)
% ============================================================
if POLISH_PASS || (USE_NEURAL_DENOISE && ~nn_ok)
    disp(' ');
    disp('--- STAGE C: residual-noise polish pass ---');
    P2 = W;
    P2.oversub           = 1.4;
    P2.gain_power        = 1.0;
    P2.speech_floor_db   = -18;
    P2.hf_floor_db       = -16;
    P2.pause_floor_db    = -30;
    P2.pause_floor_hf_db = -35;
    P2.label = 'polish';
    enhanced = spectral_denoise(enhanced, Fs, P2);
end
enhanced = enhanced / (max(abs(enhanced)) + eps);
