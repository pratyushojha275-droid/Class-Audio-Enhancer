%% ============================================================
% 8. SPEECH-TO-TEXT TRANSCRIPTION & TOPIC EXTRACTION
% ============================================================

disp(' ');
disp('--- MODULE 3: SPEECH-TO-TEXT & TOPIC EXTRACTION ---');

%% ---- OUTPUT FILE PATHS ---------------------------------------

txt_path = fullfile(OUTPUT_DIR, '03_full_transcript.txt');
csv_path = fullfile(OUTPUT_DIR, '03_transcript_words.csv');
topic_out_path = fullfile(OUTPUT_DIR, '04_topic_extracted.wav');

% Do not delete old output files before successful processing.
% This protects the previous transcript if an error occurs.

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

fprintf('\nTranscript destination:\n%s\n', txt_path);

%% ---- USER INPUT ----------------------------------------------

topic_input = strtrim(input( ...
    ['Enter topic keyword to extract (e.g., Sokovia) ', ...
     'OR PRESS ENTER to use the whole audio: '], 's'));

extraction_success = false;
transcript_saved = false;

%% ---- STEP 1: TRANSCRIBE AUDIO --------------------------------

try

    stt_input = enhanced;

    if STT_ON_ORIGINAL
        stt_input = original_audio;
    end

    % IMPORTANT:
    % Restore the original transcription method.
    % Do not replace this with a new direct speech2text call.

    [words, w_start, w_end] = transcribe_words( ...
        stt_input, Fs, STT_MODEL, WHISPER_SIZE, ...
        CHUNK_SEC, PAD_SEC, CACHE_FILE);

    if isempty(words)
        error('transcribe_words returned no words.');
    end

    %% ---- STEP 2: PREPARE TRANSCRIPT --------------------------

    words = string(words(:));
    w_start = w_start(:);
    w_end = w_end(:);

    if numel(words) ~= numel(w_start) || ...
       numel(words) ~= numel(w_end)

        error('Word count and timestamp count do not match.');
    end

    % Remove empty entries while keeping timestamps aligned
    valid_words = strlength(strtrim(words)) > 0;

    words = words(valid_words);
    w_start = w_start(valid_words);
    w_end = w_end(valid_words);

    if isempty(words)
        error('No valid words remain after cleaning the transcript.');
    end

    transcript_text = strjoin(words, ' ');

    %% ---- STEP 3: SAVE TXT BEFORE CSV -------------------------

    % Write to a temporary file first.
    % The existing full transcript is kept until this succeeds.

    tmp_txt_path = fullfile(OUTPUT_DIR, ...
        '03_full_transcript_temp.txt');

    fid = fopen(tmp_txt_path, 'w', 'n', 'UTF-8');

    if fid == -1
        error(['Cannot create transcript TXT. Check folder ', ...
               'permissions: %s'], OUTPUT_DIR);
    end

    fprintf(fid, '%s\n', char(transcript_text));

    close_status = fclose(fid);

    if close_status ~= 0
        error('Could not finish writing the transcript TXT.');
    end

    % Replace the final transcript only after writing succeeds
    [move_ok, move_msg] = movefile( ...
        tmp_txt_path, txt_path, 'f');

    if ~move_ok
        error('Could not save the final transcript: %s', move_msg);
    end

    transcript_saved = true;

    fprintf('\n========================================\n');
    fprintf('TRANSCRIPT SAVED SUCCESSFULLY!\n');
    fprintf('========================================\n');
    fprintf('%s\n', txt_path);
    fprintf('========================================\n');

    fprintf('\nFirst words recognized:\n%s ...\n', ...
        char(strjoin(words(1:min(40, numel(words))), ' ')));

    % Open the TXT automatically on Windows
    if ispc
        try
            winopen(txt_path);
        catch
            fprintf('Open the TXT manually from the output folder.\n');
        end
    end

    %% ---- STEP 4: SAVE WORD TIMESTAMPS TO CSV -----------------

    % CSV failure must not cancel TXT creation.

    try

        T = table(words, w_start, w_end, ...
            'VariableNames', {'Word', 'StartTime', 'EndTime'});

        writetable(T, csv_path);

        fprintf('\nWord timestamp CSV saved to:\n%s\n', csv_path);

    catch CSV_ME

        warning('TXT was saved, but CSV export failed: %s', ...
            CSV_ME.message);

    end

    %% ---- STEP 5: SEARCH FOR THE REQUESTED TOPIC --------------

    if ~isempty(topic_input)

        match_idx = find_keyword(words, topic_input);

        if ~isempty(match_idx)

            first_mention = match_idx(1);
            last_mention = match_idx(1);

            for m = 2:numel(match_idx)

                if (w_start(match_idx(m)) - ...
                    w_end(last_mention)) <= 90.0

                    last_mention = match_idx(m);

                else
                    break;
                end
            end

            span_start = w_start(first_mention);
            span_end = w_end(last_mention);

            total_sec = numel(enhanced) / Fs;

            win_len = max(TOPIC_WINDOW_SEC, ...
                (span_end - span_start) + ...
                2 * TOPIC_MIN_PAD_SEC);

            win_len = min(win_len, total_sec);

            mid = (span_start + span_end) / 2;

            topic_start = mid - win_len / 2;
            topic_end = mid + win_len / 2;

            % Keep the extraction interval within the audio
            if topic_start < 0
                topic_end = topic_end - topic_start;
                topic_start = 0;
            end

            if topic_end > total_sec
                topic_start = topic_start - ...
                    (topic_end - total_sec);

                topic_end = total_sec;
            end

            topic_start = max(0, topic_start);

            start_sample = max(1, ...
                floor(topic_start * Fs) + 1);

            end_sample = min(numel(enhanced), ...
                floor(topic_end * Fs));

            if end_sample <= start_sample
                error('The extracted topic interval is invalid.');
            end

            topic_audio = enhanced(start_sample:end_sample);

            % Use your original fade function
            topic_audio = apply_fade(topic_audio, Fs, 10);

            audiowrite(topic_out_path, topic_audio, Fs);

            fprintf('\nTOPIC AUDIO EXTRACTED SUCCESSFULLY!\n');
            fprintf('Keyword: %s\n', topic_input);
            fprintf('Start: %.1f seconds\n', topic_start);
            fprintf('End: %.1f seconds\n', topic_end);
            fprintf('Saved to: %s\n', topic_out_path);

            extraction_success = true;

        else

            fprintf('\nKeyword "%s" was not found.\n', topic_input);
            fprintf('Check the spelling in 03_full_transcript.txt.\n');

        end
    end

catch ME

    fprintf(2, '\nSPEECH-TO-TEXT ERROR:\n%s\n', ME.message);

    if ~isempty(ME.stack)
        fprintf(2, 'File: %s\n', ME.stack(1).name);
        fprintf(2, 'Line: %d\n', ME.stack(1).line);
    end

    if transcript_saved
        fprintf('\nThe saved transcript is safe at:\n%s\n', txt_path);
    else
        fprintf(2, ['A new transcript could not be saved. ', ...
            'The previous TXT, if present, was not intentionally deleted.\n']);
    end

end

%% ---- STEP 6: SAVE WHOLE ENHANCED AUDIO IF NEEDED -------------

if isempty(topic_input) || ~extraction_success

    if isempty(topic_input)
        disp('No topic entered. Saving the complete enhanced audio.');
    else
        disp('Topic not extracted. Saving the complete enhanced audio.');
    end

    audiowrite(topic_out_path, enhanced, Fs);

    fprintf('Audio saved to:\n%s\n', topic_out_path);

end

disp('--- MODULE 3 FINISHED ---');
