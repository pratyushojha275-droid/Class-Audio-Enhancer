%% ============================================================
% CLASS AUDIO ENHANCER V4
% CRYSTAL-CLEAR PROFESSOR VOICE + COOLER/FAN NOISE REMOVAL PRESET
% Group 10 - DSP Project
%% ============================================================

clc;
clear;
close all;

%% ---- OUTPUT FOLDER -------------------------------------------

home_dir = getenv('USERPROFILE');

if isempty(home_dir)
    home_dir = getenv('HOME');
end

OUTPUT_DIR = fullfile(home_dir, 'Desktop', 'dsp_project');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

%% ---- NOISE REDUCTION PRESET ----------------------------------
%
% 1 = Gentle
% 2 = Clear voice + cooler noise removed  (recommended, default)
% 3 = Maximum noise removal (use only if the cooler is still audible)
%
% The idea of preset 2:
%   - The cooler leaves BOTH low-mid noise AND a "shhhh" hiss above 4 kHz. The hiss above
%     4 kHz is what stayed audible while the professor talked, so the high-frequency
%     floor is now as deep as the low one and the neural stage handles the top end too.
%   - Cleaning removes voice body/brightness as a side effect, so a new AUTO TONE BALANCE
%     step (04_stage_B_neural.m) measures the voice and restores a natural spectrum.
%   - Between words the gate pushes everything down by 60 dB -> cooler = silence.

NOISE_LEVEL = 2;

switch NOISE_LEVEL

    case 1
        NOISE_OVERSUB   = 1.6;
        GAIN_POWER      = 1.0;
        SPEECH_FLOOR_DB = -16;     % below 4 kHz
        HF_FLOOR_DB     = -16;     % 4 kHz and above

        NEURAL_PASSES   = 1;
        NEURAL_LOW_MIX  = 0.60;    % neural share below NEURAL_SPLIT_HZ
        NEURAL_HIGH_MIX = 0.30;    % neural share above NEURAL_SPLIT_HZ
        POLISH_PASS     = false;

        VG_DOMINANT_DB  = 42;
        VG_PAUSE_DB     = -35;

    case 2
        NOISE_OVERSUB   = 2.2;     % subtract 2.2x the estimated cooler noise
        GAIN_POWER      = 1.4;     % sharper: strong bins stay, noisy bins go
        SPEECH_FLOOR_DB = -26;     % deep cut below 4 kHz
        HF_FLOOR_DB     = -30;     % deep cut above 4 kHz (this is where the audible hiss was)

        NEURAL_PASSES   = 1;
        NEURAL_LOW_MIX  = 1.00;    % fully neural in the cooler region
        NEURAL_HIGH_MIX = 0.85;    % mostly neural on top as well (it removes the hiss)
        POLISH_PASS     = false;   % polish pass dulls the voice; the gate does that job

        VG_DOMINANT_DB  = 38;
        VG_PAUSE_DB     = -60;     % cooler between words -> practically silent

    otherwise
        NOISE_OVERSUB   = 2.4;
        GAIN_POWER      = 1.5;
        SPEECH_FLOOR_DB = -30;
        HF_FLOOR_DB     = -34;

        NEURAL_PASSES   = 1;
        NEURAL_LOW_MIX  = 1.00;
        NEURAL_HIGH_MIX = 0.95;
        POLISH_PASS     = true;

        VG_DOMINANT_DB  = 30;
        VG_PAUSE_DB     = -70;
end

%% ---- SAMPLE RATE ---------------------------------------------

PROC_FS = 16000;

%% ---- SPEECH-TO-TEXT SETTINGS ---------------------------------
% (08_transcription_topic_extraction.m now has its own settings; these are kept
%  only so nothing else breaks.)

STT_MODEL    = "whisper";
WHISPER_SIZE = "small";
STT_LANGUAGE = "english";

CHUNK_SEC = 30;
PAD_SEC   = 2;

CACHE_FILE      = fullfile(OUTPUT_DIR, 'stt_cache.mat');
STT_ON_ORIGINAL = true;

%% ---- PRE-FILTER ----------------------------------------------
% High-pass removes cooler rumble. Narrow notches remove tonal fan/motor hum
% without touching the voice (Q is high = notch is only a few Hz wide).

HP_CUTOFF = 90;
HP_ORDER  = 4;

AUTO_NOTCH  = true;
TONE_MIN_DB = 10;
TONE_MAX_N  = 6;
NOTCH_Q     = 60;

%% ---- STAGE A: WIENER FILTER ----------------------------------

OVERLAP  = 0.75;
ALPHA_DD = 0.98;

NOISE_PCT = 8;              % noise profile = quietest 8% of the recording

NOISE_TRACK      = true;
NOISE_TRACK_RATE = 0.01;

% 3 bins (~94 Hz) keeps male-voice harmonics sharp. 5 bins smeared them, which
% both left noise BETWEEN the harmonics and made the voice sound breathy/dull.
GAIN_SMOOTH_BINS = 3;

%% ---- MINIMUM-STATISTICS NOISE TRACKING ------------------------

MS_ON = true;

MS_SMOOTH  = 0.92;
MS_SUB_SEC = 0.40;
MS_NUM_SUB = 6;

MS_BIAS = 1.30;             % was 1.10: noise was under-estimated -> cooler stayed
MS_CAP  = 5.0;              % was 3.5

BASE_WEIGHT = 1.00;         % was 0.90: trust the measured cooler profile fully

%% ---- STAGE A: INTERNAL GATE ----------------------------------

GATE_LO_DB = 6;
GATE_HI_DB = 12;

GATE_LEAD_S = 0.05;
GATE_HOLD_S = 0.12;
GATE_RAMP_S = 0.14;

PAUSE_FLOOR_DB    = -40;
PAUSE_FLOOR_HF_DB = -40;

%% ---- STAGE B: SPEECH ENHANCEMENT (04_stage_B_neural.m) -------------

USE_NEURAL_DENOISE = true;

NEURAL_MIX = 0.30;                 % (not used by the current stage B, kept for compatibility)

NEURAL_SPLIT_HZ    = 1800;         % below: cooler region (NEURAL_LOW_MIX), above: detail (NEURAL_HIGH_MIX)
NEURAL_CHUNK_SEC   = 20;
NEURAL_OVERLAP_SEC = 1;

%% ---- AUTO TONE BALANCE (end of 04_stage_B_neural.m) -------------

AUTO_TONE_MATCH   = true;

TONE_MAX_BOOST_DB = 4;
TONE_MAX_CUT_DB   = 3;

TONE_AMOUNT       = 0.25;

%% ---- STAGE D: VOICE GATE -------------------------------------

VG.enable = true;

VG.band = [150 5000];

VG.snr_db = 8;                     % must stand 8 dB above the residual floor to count as speech

VG.dominant_db = VG_DOMINANT_DB;

VG.min_speech_s = 0.08;

% generous lead/hold/ramp: word starts and endings are never clipped
VG.lead_s = 0.08;
VG.hold_s = 0.20;
VG.ramp_s = 0.15;

VG.smooth_blocks = 7;

VG.pause_db = VG_PAUSE_DB;

%% ---- CLARITY EQUALIZATION ------------------------------------
% Clarity EQ (applied AFTER the noise stages, so noise reduction is untouched).
% Fixes the dull sound: tames the 650 Hz "honk", fills 1 kHz and the 3-6 kHz consonant range.

ENABLE_VOICE_EQ = true;

% Mild reduction of boxiness; preserve the voice body
EQ_LOW_CUT_HZ = 650;
EQ_LOW_CUT_DB = -1.5;

% Presence: make spoken words sound more forward
EQ_PRESENCE_HZ = 1800;
EQ_PRESENCE_DB = 2.5;

% Clarity: improve consonant intelligibility
EQ_CLARITY_HZ = 3200;
EQ_CLARITY_DB = 2.0;

% Do not aggressively boost the high-frequency hiss region
EQ_AIR_HZ = 5500;
EQ_AIR_DB = 0.0;

%% ---- LOUDNESS AND MASTERING -------------------------------

LV.level_win = 1.0;

LV.max_boost_db = 8;
LV.max_cut_db   = 8;

LV.no_pause_boost = true;

LV.target_dbfs = -24;

% a little more evening-out: quiet syllables become clearly audible
LV.comp_thr_db = -16;
LV.comp_ratio  = 2.0;

LV.target_lufs = -18;

LV.ceiling_dbfs = -1;

%% ---- TOPIC EXTRACTION ----------------------------------------

TOPIC_WINDOW_SEC  = 75;
TOPIC_MIN_PAD_SEC = 15;

%% ---- CONFIGURATION SUMMARY -----------------------------------

fprintf('\n============================================\n');
fprintf('CRYSTAL-CLEAR VOICE / NO-COOLER PRESET\n');
fprintf('============================================\n');

fprintf('Noise level       : %d\n', NOISE_LEVEL);
fprintf('High-pass cutoff  : %d Hz (order %d)\n', HP_CUTOFF, HP_ORDER);
fprintf('Neural enhancing  : %d (low mix %.2f / high mix %.2f, split %d Hz)\n', ...
        USE_NEURAL_DENOISE, NEURAL_LOW_MIX, NEURAL_HIGH_MIX, NEURAL_SPLIT_HZ);
fprintf('Extra polish pass : %d\n', POLISH_PASS);
fprintf('Floors (low/high) : %d dB / %d dB\n', SPEECH_FLOOR_DB, HF_FLOOR_DB);
fprintf('Auto tone balance : %d (amount %.1f)\n', AUTO_TONE_MATCH, TONE_AMOUNT);
fprintf('Pause attenuation : %d dB\n', VG_PAUSE_DB);
fprintf('Presence EQ       : %.1f dB\n', EQ_PRESENCE_DB);
fprintf('Clarity EQ        : %.1f dB\n', EQ_CLARITY_DB);
fprintf('Air EQ            : %.1f dB\n', EQ_AIR_DB);
fprintf('Output folder     : %s\n', OUTPUT_DIR);

fprintf('============================================\n\n');
