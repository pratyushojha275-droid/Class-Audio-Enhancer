clc;
clear;
close all;

%% ============================================================
% CLASS AUDIO ENHANCER  v4  -  "PROFESSOR VOICE ONLY"
% Group 10 - DSP Project
% Toolboxes: Signal Processing, Audio, Deep Learning
%
% WHY v3 STILL LEFT NOISE (and what v4 does about it):
%  1. The noise profile was a fixed snapshot taken from pauses. Class noise
%     (fan, AC, chatter, projector, room echo) changes all the time and is
%     loudest exactly WHEN the professor talks. v4 adds a continuous
%     minimum-statistics noise tracker that follows the noise even while
%     the professor is speaking.
%  2. Nothing cleaned the noise that is left between words after the neural
%     stage. v4 adds a VOICE GATE computed from the already-cleaned signal,
%     so anything that is not the professor's (loud, close) voice is pushed
%     down by 60+ dB instead of 35-40 dB.
%  3. Far-away voices (students) are quieter than the professor, who is
%     closest to the mic. The voice gate also removes anything far below
%     the professor's normal speaking level ("dominant speaker" rule).
%  4. Neural denoiser now runs in safe chunks (long lectures no longer run
%     out of memory), and can run 2 passes.
%  5. Everything is processed at 16 kHz. Speech needs nothing above 8 kHz,
%     so all the hiss up there is gone by definition, and it runs ~3x faster.
%
% ONE KNOB TO TURN:  NOISE_LEVEL below (1 gentle / 2 strong / 3 maximum).
% ============================================================

%% ---- OUTPUT FOLDER ---------------------------------------------------
home_dir = getenv('USERPROFILE');
if isempty(home_dir), home_dir = getenv('HOME'); end
OUTPUT_DIR = fullfile(home_dir, 'Desktop', 'dsp_project');
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

%% ============================================================
% >>> MAIN KNOB <<<
% 3 = MAXIMUM  : removes practically everything except the professor.
%                If the voice starts to sound thin/robotic, go to 2.
% 2 = STRONG   : very clean, more natural voice.
% 1 = GENTLE   : light cleanup only.
% ============================================================
NOISE_LEVEL = 3;

switch NOISE_LEVEL
    case 1
        NOISE_OVERSUB = 1.6;  GAIN_POWER = 1.0;  SPEECH_FLOOR_DB = -16;  HF_FLOOR_DB = -14;
        NEURAL_PASSES = 1;    POLISH_PASS = false;
        VG_DOMINANT_DB = 35;  VG_PAUSE_DB = -40;
    case 2
        NOISE_OVERSUB = 2.0;  GAIN_POWER = 1.25; SPEECH_FLOOR_DB = -22;  HF_FLOOR_DB = -20;
        NEURAL_PASSES = 1;    POLISH_PASS = true;
        VG_DOMINANT_DB = 30;  VG_PAUSE_DB = -50;
    otherwise   % 3
        NOISE_OVERSUB = 2.4;  GAIN_POWER = 1.5;  SPEECH_FLOOR_DB = -26;  HF_FLOOR_DB = -24;
        NEURAL_PASSES = 2;    POLISH_PASS = true;
        VG_DOMINANT_DB = 24;  VG_PAUSE_DB = -65;
end

%% ---- SAMPLE RATE USED FOR ALL PROCESSING -------------------------------
PROC_FS = 16000;     % Hz. Keep 16000 (the neural denoiser and speech-to-text both use it).

%% ---- SPEECH-TO-TEXT SETTINGS -------------------------------------------
STT_MODEL    = "whisper";     % "wav2vec2.0" (lighter) or "whisper"
WHISPER_SIZE = "base";        % whisper only. MATLAB's default "large" is very heavy on a laptop
CHUNK_SEC    = 15;
PAD_SEC      = 1;
CACHE_FILE   = fullfile(OUTPUT_DIR, 'stt_cache.mat');
STT_ON_ORIGINAL = true;       % true = transcribe the untouched audio. Recommended now: the cleaned
                              % audio has (almost) digital silence between words and Whisper can
                              % "hallucinate" text in pure silence. Timestamps are identical anyway.

%% ---- PRE-FILTER: rumble + buzz -----------------------------------------

HP_CUTOFF   = 90;    % Lower than 120 Hz to preserve more natural professor voice
HP_ORDER    = 5;     % Moderate slope; avoids excessive removal of low speech body

AUTO_NOTCH  = true;  % Find this recording's own stationary hum/buzz lines
TONE_MIN_DB = 8;     % A tone must stick out this many dB above its neighbourhood
TONE_MAX_N  = 10;    % Notch at most this many tones
NOTCH_Q     = 40;    % Narrow notches; removes tones without damaging nearby speech

%% ---- STAGE A: WIENER FILTER WITH CONTINUOUS NOISE TRACKING ---------------

OVERLAP          = 0.75;
ALPHA_DD         = 0.98;

NOISE_PCT        = 10;
NOISE_TRACK      = true;
NOISE_TRACK_RATE = 0.02;

GAIN_SMOOTH_BINS = 3;

% Minimum-statistics tracker
% Keep it active for changing background noise, but make it less aggressive
MS_ON            = true;

MS_SMOOTH        = 0.90;
MS_SUB_SEC       = 0.30;
MS_NUM_SUB       = 6;

MS_BIAS          = 1.25;   % was 1.6 -> less likely to mistake speech detail for noise
MS_CAP           = 5;      % was 8 -> limits excessive noise estimation

BASE_WEIGHT      = 0.85;   % trust the pause-based noise profile more

% Pre-gate used INSIDE stage A
GATE_LO_DB       = 6;
GATE_HI_DB       = 12;

GATE_LEAD_S      = 0.04;
GATE_HOLD_S      = 0.10;
GATE_RAMP_S      = 0.10;

% Keep pauses very quiet
PAUSE_FLOOR_DB    = -40;
PAUSE_FLOOR_HF_DB = -45;

%% ---- STAGE B: NEURAL DENOISER (Audio Toolbox denoiseNet) ------------------

USE_NEURAL_DENOISE = true;

NEURAL_MIX         = 0.30;   % 30% neural + 70% Wiener
NEURAL_CHUNK_SEC   = 60;
NEURAL_OVERLAP_SEC = 2;

%% ---- STAGE D: VOICE GATE (removes everything that is not the professor) ---

VG.enable        = true;

VG.band          = [250 4000];

VG.snr_db        = 10;

% Keep this moderate so quiet syllables are not removed
VG.dominant_db   = VG_DOMINANT_DB;

VG.min_speech_s  = 0.06;

VG.lead_s        = 0.06;
VG.hold_s        = 0.15;
VG.ramp_s        = 0.12;

VG.smooth_blocks = 5;

% Do not make pauses completely digital-silent
VG.pause_db      = VG_PAUSE_DB;

%% ---- CLARITY EQ --------------------------------------------------------

ENABLE_VOICE_EQ = true;

EQ_LOW_CUT_HZ   = 300;
EQ_LOW_CUT_DB   = -1.0;    % less low-mid removal

EQ_PRESENCE_HZ  = 1500;
EQ_PRESENCE_DB  = 2.5;     % improves speech/consonant clarity

EQ_CLARITY_HZ   = 3000;
EQ_CLARITY_DB   = 3.0;     % improves intelligibility

EQ_AIR_HZ       = 5500;
EQ_AIR_DB       = 1.5;     % adds brightness without excessive hiss

%% ---- LEVELING / LOUDNESS -------------------------------------------------

LV.level_win       = 1.0;

LV.max_boost_db    = 10;
LV.max_cut_db      = 10;

LV.no_pause_boost  = true;

LV.target_dbfs     = -24;

LV.comp_thr_db     = -12;
LV.comp_ratio      = 2;

LV.target_lufs     = -18;

LV.ceiling_dbfs    = -1;

%% ---- TOPIC EXTRACTION ------------------------------------------------------
TOPIC_WINDOW_SEC  = 75;
TOPIC_MIN_PAD_SEC = 15;

