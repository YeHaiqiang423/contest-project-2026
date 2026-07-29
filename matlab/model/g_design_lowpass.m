function h = g_design_lowpass(num_taps, cutoff_hz, fs_hz, beta)
%G_DESIGN_LOWPASS Windowed-sinc low-pass used by model and RTL tooling.

    if rem(num_taps, 2) == 0
        error('num_taps must be odd for an integer group delay.');
    end
    order = num_taps-1;
    tap_index = 0:order;
    centered_index = tap_index-order/2;
    normalized_cutoff = 2*cutoff_hz/fs_hz;
    ideal = normalized_cutoff*local_sinc(normalized_cutoff*centered_index);
    radius = 2*tap_index/order-1;
    window = besseli(0, beta*sqrt(max(0, 1-radius.^2)))/besseli(0, beta);
    h = ideal.*window;
    h = h/sum(h);
end

function y = local_sinc(x)
    y = ones(size(x));
    nonzero = x ~= 0;
    y(nonzero) = sin(pi*x(nonzero))./(pi*x(nonzero));
end
