function refDB = loadBanknoteDatabase()
% LOADBANKNOTEDATABASE - טוען תמונות רפרנס של שטרות + חילוץ צבע דומיננטי
    
    refPath = fullfile('data', 'ReferenceBanknotes');
    
    % בדיקה: האם התיקייה קיימת?
    if ~isfolder(refPath)
        warning('Banknote reference folder not found: %s', refPath);
        warning('Creating empty reference database. Add images to enable SURF matching.');
        refDB = [];
        return;
    end

    files = dir(fullfile(refPath, '*.jpg'));
    if isempty(files)
        files = [files; dir(fullfile(refPath, '*.png'))];
    end
    
    refDB = [];
    
    fprintf('Loading banknote reference images from: %s\n', refPath);
    
    for i = 1:length(files)
        filename = files(i).name;
        fullName = fullfile(files(i).folder, filename);
        imgColor = imread(fullName);
        if size(imgColor,3) == 3
            img = rgb2gray(imgColor);
        else
            img = imgColor;
            imgColor = cat(3, img, img, img); % המר לצבע אם צריך
        end
        
        % זיהוי שם השטר לפי שם הקובץ
        fLower = lower(filename);
        name = 'Unknown';
        
        % ILS
        if contains(fLower, '20nis') || contains(fLower, '20shekel')
            name='20 NIS';
        elseif contains(fLower, '50nis') || contains(fLower, '50shekel')
            name='50 NIS';
        elseif contains(fLower, '100nis') || contains(fLower, '100shekel')
            name='100 NIS';
        elseif contains(fLower, '200nis') || contains(fLower, '200shekel')
            name='200 NIS';
        
        % EUR
        elseif contains(fLower, '5euro')
            name='5 Euro';
        elseif contains(fLower, '10euro')
            name='10 Euro';
        elseif contains(fLower, '20euro')
            name='20 Euro';
        elseif contains(fLower, '50euro')
            name='50 Euro';
        elseif contains(fLower, '100euro')
            name='100 Euro';
        elseif contains(fLower, '200euro')
            name='200 Euro';
        end
        
        try
            points = detectSURFFeatures(img, 'MetricThreshold', 200);
            [features, ~] = extractFeatures(img, points);
            
            % === חילוץ צבע דומיננטי ===
            [dominantHue, hueRange, dominantSat] = extractDominantColor(imgColor);
            
            refDB(end+1).Name = name;
            refDB(end).Features = features;
            refDB(end).DominantHue = dominantHue;      % ערך H דומיננטי (0-1)
            refDB(end).HueRange = hueRange;            % [minH, maxH]
            refDB(end).DominantSaturation = dominantSat;
            
            fprintf('  Loaded: %-15s (%d features) | Hue: %.2f [%.2f-%.2f]\n', ...
                name, length(points), dominantHue, hueRange(1), hueRange(2));
        catch ME
            warning('  Failed to extract features from: %s - %s', filename, ME.message);
        end
    end
    
    if isempty(refDB)
        fprintf('  No banknote references loaded. Detection will work but without SURF matching.\n');
    end
end

function [dominantHue, hueRange, dominantSat] = extractDominantColor(img)
% חילוץ צבע דומיננטי מתמונה
    hsv = rgb2hsv(img);
    H = hsv(:,:,1);
    S = hsv(:,:,2);
    V = hsv(:,:,3);
    
    % התעלם מפיקסלים חסרי צבע (saturation נמוכה) או כהים מדי
    validMask = (S > 0.15) & (V > 0.2);
    
    if sum(validMask(:)) < 100
        % אם אין מספיק פיקסלים תקינים, קח את כולם
        validMask = true(size(H));
    end
    
    validH = H(validMask);
    validS = S(validMask);
    
    % חישוב ממוצע מעגלי של Hue (כי 0 ו-1 הם אותו צבע - אדום)
    sinH = mean(sin(2*pi*validH));
    cosH = mean(cos(2*pi*validH));
    dominantHue = mod(atan2(sinH, cosH) / (2*pi), 1);
    
    % חישוב טווח Hue (percentile 10-90)
    hueMin = prctile(validH, 10);
    hueMax = prctile(validH, 90);
    
    % הרחב קצת את הטווח
    hueMargin = 0.05;
    hueRange = [max(0, hueMin - hueMargin), min(1, hueMax + hueMargin)];
    
    % Saturation ממוצעת
    dominantSat = mean(validS);
end
