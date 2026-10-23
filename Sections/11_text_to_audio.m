%% ============================================================
% 11. TEXT-TO-AUDIO (TTS) CONVERTER
% ============================================================
disp(' ');
disp('--- MODULE 8: TEXT TO AUDIO ---');

if ~ispc
    disp('Module 8 uses Windows System.Speech and is not available on this OS. Skipping.');
else
    disp('Opening file selector for Text-to-Audio conversion...');
    [txt_file, txt_sel_path] = uigetfile('*.txt', 'Select the Text File you want to convert to Audio');

    if isequal(txt_file, 0)
        disp('No text file selected. Skipping Text-to-Audio.');
    else
        text_content = fileread(fullfile(txt_sel_path, txt_file));
        audio_out_path = fullfile(OUTPUT_DIR, '08_text_to_audio.wav');

        NET.addAssembly('System.Speech');
        synth = System.Speech.Synthesis.SpeechSynthesizer();
        synth.SetOutputToWaveFile(audio_out_path);
        synth.Speak(text_content);
        synth.Dispose();

        fprintf('SUCCESS: Text audio saved to: %s\n', audio_out_path);
    end
end
