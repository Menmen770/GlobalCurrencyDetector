function refDB = loadCoinDatabase()
    % הפונקציה מחפשת את תמונות הרפרנס בתוך תיקיית data
    
    % 1. הגדרת הנתיב החדש
    refPath = fullfile('data', 'ReferenceCoins');
    
    % 2. בדיקת בטיחות: האם התיקייה קיימת?
    if ~isfolder(refPath)
        error('Error: The folder "%s" was not found. Please check folder structure.', refPath);
    end

    files = dir(fullfile(refPath, '*.jpg')); 
    refDB = [];
    
    fprintf('Loading reference images from: %s\n', refPath);
    
    for i = 1:length(files)
        filename = files(i).name;
        fullName = fullfile(files(i).folder, filename);
        img = imread(fullName);
        if size(img,3) == 3, img = rgb2gray(img); end
        
        % זיהוי שם המטבע לפי שם הקובץ
        fLower = lower(filename);
        name = 'Unknown';
        
        if contains(fLower, '1nis'), name='1 NIS';
        elseif contains(fLower, '2euro'), name='2 Euro';
        elseif contains(fLower, '1euro'), name='1 Euro';
        elseif contains(fLower, '10nis'), name='10 NIS';
        elseif contains(fLower, '5nis'), name='5 NIS';
        elseif contains(fLower, 'half'), name='Half NIS';
        elseif contains(fLower, 'dime'), name='Dime';
        elseif contains(fLower, 'quarter'), name='Quarter';
        elseif contains(fLower, 'penny'), name='Penny';
        elseif contains(fLower, 'nickel'), name='Nickel';
        elseif contains(fLower, '50cent'), name='50 Cent EUR';
        elseif contains(fLower, '20cent'), name='20 Cent EUR';
        elseif contains(fLower, '10cent'), name='10 Cent EUR';
        elseif contains(fLower, '10ag'), name='10 Agorot';
        end
        
        points = detectSURFFeatures(img, 'MetricThreshold', 200); % הורדת סף למציאת יותר נקודות
        [features, ~] = extractFeatures(img, points);
        
        refDB(end+1).Name = name;
        refDB(end).Features = features;
        
        % הוספתי הדפסה מעוצבת כדי שיהיה נעים בעין
        fprintf('  Loaded: %-15s (%d features)\n', name, length(points));
    end
end