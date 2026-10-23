%% ============================================================
% 8. SPEECH-TO-TEXT TRANSCRIPTION & TOPIC EXTRACTION
% ============================================================
disp(' ');
disp('--- MODULE 3: SPEECH-TO-TEXT & TOPIC EXTRACTION ---');

topic_out_path = fullfile(OUTPUT_DIR, '04_topic_extracted.wav');
if exist(topic_out_path, 'file')
    delete(topic_out_path);
end

topic_input = strtrim(input('Enter topic keyword to extract (e.g., Sokovia) OR PRESS ENTER to listen to the whole audio: ', 's'));
extraction_success = false;

try
    stt_input = enhanced;
    if STT_ON_ORIGINAL, stt_input = original_audio; end

    [words, w_start, w_end] = transcribe_words(stt_input, Fs, STT_MODEL, WHISPER_SIZE, ...
                                               CHUNK_SEC, PAD_SEC, CACHE_FILE);
    if isempty(words)
        error('speech2text returned no words for the whole file.');
    end

    csv_path = fullfile(OUTPUT_DIR, '03_transcript_words.csv');
    writetable(table(words, w_start, w_end), csv_path);
    fprintf('Word timestamps saved to: %s\n', csv_path);

    txt_path = fullfile(OUTPUT_DIR, '03_full_transcript.txt');
    fid = fopen(txt_path, 'w');
    if fid ~= -1
        fprintf(fid, '%s', strjoin(words, ' '));
        fclose(fid);
        fprintf('>>> SUCCESS! Transcript text file saved to: %s\n', txt_path);
        if ispc
            winopen(txt_path);
        else
            edit(txt_path);
        end
    end

    if ~isempty(topic_input)
        match_idx = find_keyword(words, topic_input);

        if ~isempty(match_idx)
            first_mention = match_idx(1);
            last_mention  = match_idx(1);
            for m = 2:numel(match_idx)
                if (w_start(match_idx(m)) - w_end(last_mention)) <= 90.0
                    last_mention = match_idx(m);
                else
                    break;
                end
            end

            span_start = w_start(first_mention);
            span_end   = w_end(last_mention);
            total_sec  = length(enhanced) / Fs;
            win_len    = max(TOPIC_WINDOW_SEC, (span_end - span_start) + 2*TOPIC_MIN_PAD_SEC);
            win_len    = min(win_len, total_sec);
            mid        = (span_start + span_end) / 2;
            topic_start = mid - win_len/2;
            topic_end   = mid + win_len/2;
            if topic_start < 0
                topic_end   = topic_end - topic_start;
                topic_start = 0;
            end
            if topic_end > total_sec
                topic_start = topic_start - (topic_end - total_sec);
                topic_end   = total_sec;
            end

            start_sample = max(1, round(topic_start * Fs));
            end_sample   = min(length(enhanced), round(topic_end * Fs));

            topic_audio = apply_fade(enhanced(start_sample:end_sample), Fs, 10);
            audiowrite(topic_out_path, topic_audio, Fs);
            fprintf('\n>>> SUCCESS! "%s" extracted from %.1f sec to %.1f sec (%.0f sec block).\n', ...
                    topic_input, topic_start, topic_end, topic_end - topic_start);
            extraction_success = true;
        else
            fprintf('Keyword "%s" not found. Open 03_full_transcript.txt to see how the recognizer spelled it.\n', topic_input);
        end
    end
catch ME
    fprintf(2, '\nSpeech-to-text failed: %s\n', ME.message);
    disp('Defaulting to whole audio.');
end

if isempty(topic_input) || ~extraction_success
    if isempty(topic_input)
        disp('>>> No topic entered. Saving the entire enhanced audio file.');
    else
        disp('>>> Topic not extracted. Saving the entire enhanced audio file instead.');
    end
    audiowrite(topic_out_path, enhanced, Fs);
end
