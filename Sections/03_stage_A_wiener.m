%% ============================================================
% 3. STAGE A: WIENER FILTER + CONTINUOUS NOISE TRACKING
% ============================================================
disp(' ');
disp('--- STAGE A: Wiener filter with continuous noise tracking ---');

W = struct();
W.frame_len  = 2^round(log2(0.025 * Fs));
W.hop        = round(W.frame_len * (1 - OVERLAP));
W.alpha_dd   = ALPHA_DD;
W.oversub    = NOISE_OVERSUB;
W.gain_power = GAIN_POWER;
W.speech_floor_db = SPEECH_FLOOR_DB;
W.hf_floor_db     = HF_FLOOR_DB;
W.noise_pct        = NOISE_PCT;
W.noise_track      = NOISE_TRACK;
W.noise_track_rate = NOISE_TRACK_RATE;
W.gain_smooth_bins = GAIN_SMOOTH_BINS;
W.ms_on     = MS_ON;
W.ms_smooth = MS_SMOOTH;
W.ms_sub_s  = MS_SUB_SEC;
W.ms_num_sub = MS_NUM_SUB;
W.ms_bias   = MS_BIAS;
W.ms_cap    = MS_CAP;
W.base_weight = BASE_WEIGHT;
W.gate_lo_db  = GATE_LO_DB;   W.gate_hi_db  = GATE_HI_DB;
W.gate_lead_s = GATE_LEAD_S;  W.gate_hold_s = GATE_HOLD_S;  W.gate_ramp_s = GATE_RAMP_S;
W.pause_floor_db    = PAUSE_FLOOR_DB;
W.pause_floor_hf_db = PAUSE_FLOOR_HF_DB;
W.label = 'main';
hop_size = W.hop;

enhanced = spectral_denoise(cleaned_initial, Fs, W);
clear cleaned_initial;
