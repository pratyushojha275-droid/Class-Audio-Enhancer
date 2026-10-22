%% ============================================================
% 1. PRE-PROCESSING
% ============================================================
disp('--- MODULE 1: PRE-PROCESSING ---');
[file, path] = uigetfile({'*.wav;*.mp3;*.m4a;*.flac;*.mp4', 'Media Files (*.wav, *.mp3, *.m4a, *.flac, *.mp4)'; ...
                          '*.*', 'All Files (*.*)'}, ...
                          'Select Lecture/Podcast Media');
if isequal(file, 0)
    disp('No media file selected. Exiting...');
    return;
end

[audio, Fs_in] = audioread(fullfile(path, file));
audio = mean(audio, 2);            % mono (works for 1, 2 or more channels)
Fs = PROC_FS;
if Fs_in ~= Fs
    fprintf('Resampling %d Hz -> %d Hz for processing...\n', Fs_in, Fs);
    audio = resample(audio, Fs, Fs_in);
end
audio = audio(:);

peak0 = max(abs(audio));
if peak0 == 0
    error('The selected file is completely silent.');
end
audio = audio / peak0;
original_audio = audio;

audiowrite(fullfile(OUTPUT_DIR, '01_original_audio.wav'), original_audio, Fs);
fprintf('Processing rate    : %d Hz (input file was %d Hz)\n', Fs, Fs_in);
fprintf('Duration           : %.2f minutes\n', length(audio)/Fs/60);
fprintf('Original audio saved to: %s\n', OUTPUT_DIR);
fprintf('Noise removal level: %d  (1 gentle / 2 strong / 3 maximum)\n', NOISE_LEVEL);
