function [resizeImg, grayImg, blurredImg, hsvImg] = image_utils(inputImage)
% IMAGE_UTILS Preprocesses the raw image for detection.
% Inputs: 
%   inputImage - Can be a filename (string) or an image matrix.
% Outputs:
%   resizeImg  - Resized RGB image (for display and speed).
%   grayImg    - Grayscale contrast-enhanced image.
%   blurredImg - Smoothed image for Circle Detection.
%   hsvImg     - HSV converted image for Color Analysis.

    % 1. Load Image if input is a filename
    if ischar(inputImage) || isstring(inputImage)
        if ~isfile(inputImage)
            error('File not found: %s', inputImage);
        end
        rawImg = imread(inputImage);
        try
            setappdata(0, 'currentImagePath', char(inputImage));
        catch
            % Ignore if appdata is not available.
        end
    else
        rawImg = inputImage;
    end

    % 2. Resize for Performance
    % High-res phone photos (4000px+) slow down algorithms. 
    % We resize so the smallest dimension is around 1200px.
    scaleFactor = 1200 / min(size(rawImg, 1:2));
    if scaleFactor < 1
        resizeImg = imresize(rawImg, scaleFactor);
    else
        resizeImg = rawImg;
    end

    % 3. Convert to Color Spaces
    grayRaw = rgb2gray(resizeImg);
    hsvImg = rgb2hsv(resizeImg);

    % 4. Enhance Contrast
    % Using basic adjustment to make coins pop out from background
    enhancedImg = imadjust(grayRaw); 
    
    % 5. Noise Reduction
    % Gaussian blur is critical for Hough Transform (imfindcircles)
    % "Sigma" = 2.5 is based on your successful tests.
    blurredImg = imgaussfilt(enhancedImg, 2.5);
    
    grayImg = enhancedImg; % Return the sharp enhanced version for display
end