function generate_g_frame_vectors()
%GENERATE_G_FRAME_VECTORS Shared vectors for the ping-pong frame collector.

    rng(40962, 'twister');
    decimation = 4;
    frame_length = 16;
    frame_count = 2;
    input_count = decimation*frame_length*frame_count;

    input_sample = randi([-30000, 30000], input_count, 1);
    input_sample(1:8) = [-32768; -32767; -1; 0; 1; 16384; 32766; 32767];
    expected_sample = input_sample(1:decimation:end);

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    write_vector(fullfile(vector_dir, 'g_frame_input.txt'), input_sample);
    write_vector(fullfile(vector_dir, 'g_frame_expected.txt'), expected_sample);
    fprintf('Generated %d frame inputs and %d selected outputs.\n', ...
        numel(input_sample), numel(expected_sample));
end

function write_vector(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end
