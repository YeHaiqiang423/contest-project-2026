function generate_g_fft_spectrum_vectors()
%GENERATE_G_FFT_SPECTRUM_VECTORS Deterministic 4096-point FFT test frames.

    nfft = 4096;
    sample_rate_hz = 2e6;
    n = (0:nfft-1).';
    hann_q15 = int64(round((0.5-0.5*cos(2*pi*n/(nfft-1)))*32767));

    frame1 = round(800*cos(2*pi*1024*n/nfft+0.23));
    frame2 = round(1000*cos(2*pi*205*n/nfft-0.31) + ...
        300*cos(2*pi*512*n/nfft+0.77) + ...
        120*cos(2*pi*922*n/nfft-1.13));
    frame3 = round(700*cos(2*pi*10000*n/sample_rate_hz+0.41));
    frame4 = round(650*cos(2*pi*13000*n/sample_rate_hz-0.62));
    frame5 = round(900*cos(2*pi*300000*n/sample_rate_hz+0.19));
    frame6 = round(800*cos(2*pi*500000*n/sample_rate_hz+pi/2));
    frame7 = round(800*cos(2*pi*499900*n/sample_rate_hz-1.20));
    frame8 = round(800*cos(2*pi*499500*n/sample_rate_hz+2.40));
    frame9 = round(100*cos(2*pi*100000*n/sample_rate_hz+deg2rad(100)) + ...
        400*cos(2*pi*200000*n/sample_rate_hz+deg2rad(40)) + ...
        500*cos(2*pi*400000*n/sample_rate_hz));
    frame10 = round(100*cos(2*pi*100000*n/sample_rate_hz) + ...
        400*cos(2*pi*200000*n/sample_rate_hz) + ...
        500*cos(2*pi*400000*n/sample_rate_hz));

    windowed1 = apply_q15_hann(frame1, hann_q15);
    windowed2 = apply_q15_hann(frame2, hann_q15);
    windowed3 = apply_q15_hann(frame3, hann_q15);
    windowed4 = apply_q15_hann(frame4, hann_q15);
    windowed5 = apply_q15_hann(frame5, hann_q15);
    windowed6 = apply_q15_hann(frame6, hann_q15);
    windowed7 = apply_q15_hann(frame7, hann_q15);
    windowed8 = apply_q15_hann(frame8, hann_q15);
    windowed9 = apply_q15_hann(frame9, hann_q15);
    windowed10 = apply_q15_hann(frame10, hann_q15);

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    write_decimal(fullfile(vector_dir, 'g_fft_spectrum_input.txt'), ...
        [windowed1; windowed2; windowed3; windowed4; windowed5; ...
        windowed6; windowed7; windowed8; windowed9; windowed10]);
    fprintf(['Generated ten 4096-point Hann-windowed FFT frames, including ' ...
        '500 kHz phase/boundary and weak-fundamental phase regressions.\n']);
end

function output = apply_q15_hann(input, hann_q15)
    product = int64(input(:)).*hann_q15;
    output = floor((double(product)+2^14)/2^15);
end

function write_decimal(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end
