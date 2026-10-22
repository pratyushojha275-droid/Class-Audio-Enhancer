%% ============================================================
% 7. CLARITY EQ + LEVELING
% ============================================================
if ENABLE_VOICE_EQ
    disp('Applying clarity EQ...');
    [b1,a1] = peaking_eq(EQ_LOW_CUT_HZ,  0.8, EQ_LOW_CUT_DB,  Fs);
    [b2,a2] = peaking_eq(EQ_PRESENCE_HZ, 1.0, EQ_PRESENCE_DB, Fs);
    [b3,a3] = peaking_eq(EQ_CLARITY_HZ,  1.0, EQ_CLARITY_DB,  Fs);
    [b4,a4] = high_shelf_eq(EQ_AIR_HZ, EQ_AIR_DB, Fs);
    enhanced = filter(b1,a1,enhanced);
    enhanced = filter(b2,a2,enhanced);
    enhanced = filter(b3,a3,enhanced);
    enhanced = filter(b4,a4,enhanced);
end

disp('Leveling and mastering...');
enhanced = level_and_master(enhanced, Fs, is_speech, hop_size, LV);
audiowrite(fullfile(OUTPUT_DIR, '02_enhanced_lecture.wav'), enhanced, Fs);
disp('Enhanced audio saved: 02_enhanced_lecture.wav');
