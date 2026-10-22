# Class Audio Enhancer v4 — Professor Voice Enhancement

A MATLAB-based Digital Signal Processing (DSP) project designed to reduce background noise in classroom recordings and improve lecture intelligibility while preserving the professor's voice.

## Features

- High-pass filtering to reduce low-frequency rumble.
- Automatic detection and suppression of stationary hum and buzz.
- Wiener filtering with continuous noise tracking.
- Optional neural speech denoising.
- Voice gating to reduce background sounds between speech segments.
- Voice clarity equalization and loudness leveling.
- Speech-to-text transcription with word timestamps.
- Topic-based audio extraction.
- Smart revision mode to shorten long pauses.
- Waveform, frequency spectrum, loudness plots, and a quality report with detailed analysis.
- Text-to-audio conversion on supported Windows systems.

## Project Structure

```text
class_audio_enhancer_v4/
│
├── before_section_1/
│   └── 00_before_section_1.m
│
├── sections/
│   ├── 01_pre_processing.m
│   ├── 02_pre_filter.m
│   ├── 03_stage_A_wiener.m
│   ├── 04_stage_B_neural.m
│   ├── 05_stage_C_polish.m
│   ├── 06_stage_D_voice_gate.m
│   ├── 07_clarity_EQ_leveling.m
│   ├── 08_transcription_topic_extraction.m
│   ├── 09_smart_revision.m
│   ├── 10_evaluation_report.m
│   └── 11_text_to_audio.m
│
├── functions/
│   └── Local_functions.m
│
├── Run_all.m
├── class_audio_enhancer_v4_combined.m
└── README.md
```

### Folder and File Descriptions

- **`before_section_1/`** — Initialization, configuration, and processing parameters.
- **`sections/`** — The eleven sequential stages of the audio enhancement pipeline.
- **`functions/`** — Supporting DSP, denoising, transcription, and signal-processing functions.
- **`Run_all.m`** — Master runner that combines the source sections in order and executes the complete program.
- **`class_audio_enhancer_v4_combined.m`** — Generated MATLAB script containing the assembled program.

## Requirements

- MATLAB.
- Signal Processing Toolbox for filtering, spectral analysis, and related DSP operations.
- Audio Toolbox and compatible speech-processing functionality for supported denoising and transcription features.
- Compatible deep-learning support for the optional neural denoiser.
- Windows System.Speech support for the text-to-audio feature.

Feature availability depends on the MATLAB release, installed toolboxes, and supported model configuration.

## How to Run

1. Clone or download this repository.
2. Open the project folder in VS Code with the MATLAB extension installed and connected to MATLAB.
3. Ensure all source files are saved in their respective folders.
4. Open `Run_all.m`.
5. Run `Run_all.m` using the MATLAB extension.
6. Select the input lecture or podcast recording when prompted.
7. Follow the prompts for topic extraction and other available options.

The master runner assembles the source sections in their prescribed order, generates `class_audio_enhancer_v4_combined.m`, and runs the combined script.

**Run `Run_all.m`, not `Local_functions.m` or the individual section files.**

## Generated Outputs

The project can generate the following files:

| Output | Description |
|---|---|
| `01_original_audio.wav` | Input audio prepared for processing |
| `02_enhanced_lecture.wav` | Noise-reduced and leveled lecture audio |
| `03_transcript_words.csv` | Transcription with word timestamps |
| `03_full_transcript.txt` | Full speech transcript |
| `04_topic_extracted.wav` | Audio extracted around a requested topic |
| `05_smart_revision.wav` | Audio with long pauses shortened |
| `06_dsp_evaluation_plots.png` | Waveform and spectrum comparisons |
| `07_loudness_plots.png` | Loudness consistency comparison |
| `08_text_to_audio.wav` | Audio generated from a text file |

Outputs are saved to the configured `dsp_project` folder on the Desktop.

## Noise Reduction Settings

The `NOISE_LEVEL` parameter in `00_before_section_1.m` controls the processing preset:

- `1` — Gentle noise reduction.
- `2` — Strong noise reduction.
- `3` — Maximum noise reduction.

More aggressive suppression may also affect speech quality. The best setting depends on the recording and the balance between noise removal and voice clarity.

## Notes

- Test the program using a short recording before processing a full lecture.
- Some optional stages require additional MATLAB toolboxes or compatible models.
- Do not upload private lecture recordings, confidential transcripts, credentials, or other personal data to a public repository.
- The generated combined script should be regenerated through `Run_all.m` after modifying the source sections.

## Project Information

- **Project:** Class Audio Enhancer v4 — Professor Voice Enhancement
- **Group:** Group 10
- **Domain:** Digital Signal Processing (DSP)
- **Language:** MATLAB
