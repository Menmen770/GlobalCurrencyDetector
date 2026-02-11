function [centers, radii] = detector(processedImg, sensitivity)
% DETECTOR - זיהוי מטבעות פשוט וישיר (יציב, בלי ניסיונות מרובים)

    if nargin < 2
        sensitivity = 0.85;
    end

    [centers, radii, ~] = imfindcircles(processedImg, [58 120], ...
        'ObjectPolarity', 'bright', ...
        'Sensitivity', sensitivity, ...
        'Method', 'TwoStage');

    if isempty(radii)
        centers = []; radii = [];
        return;
    end
    
    % סינון בסיסי - הסר עיגולים חופפים לחלוטין
    keep = true(length(radii), 1);
    for i = 1:length(radii)
        if ~keep(i), continue; end
        for j = i+1:length(radii)
            if ~keep(j), continue; end
            dist = norm(centers(i,:) - centers(j,:));
            % רק אם העיגולים ממש זהים (מרחק < 5px)
            if dist < 5
                keep(j) = false;
            end
        end
    end
    
    centers = centers(keep, :);
    radii = radii(keep);
end