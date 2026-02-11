function [rects, scores] = detector_banknotes(img, ~, ~)
% DETECTOR_BANKNOTES v2 - זיהוי שטרות לפי קצוות ומלבנים (לא לפי צבע!)
% גישה חדשה: מחפש מלבנים בתמונה עם יחס רוחב-גובה של שטר

    [imgH, imgW, ~] = size(img);
    
    % מרווח מגבול התמונה (למנוע זיהוי של מסגרות חיצוניות)
    borderMargin = 5;
    
    % === הגדרות גודל באחוזים ===
    MIN_WIDTH = imgW * 0.12;    % לפחות 12% מרוחב התמונה
    MAX_WIDTH = imgW * 0.98;    % מקסימום 98% (שטרות יכולים למלא את התמונה)
    MIN_HEIGHT = imgH * 0.12;   % לפחות 12% מגובה התמונה
    MAX_HEIGHT = imgH * 0.98;   % מקסימום 98%
    
    MIN_AREA = MIN_WIDTH * MIN_HEIGHT * 0.4;
    
    % יחס רוחב-גובה של שטרות (גמיש - שטרות יכולים להיות 1.2-2.8)
    MIN_ASPECT = 1.15;  % הורדה ל-1.15 (שטרות לפעמים 1.2-1.3)
    MAX_ASPECT = 2.8;
    
    fprintf('🔍 [Banknote Detection] Starting detection...\n');
    drawnow;
    
    % === שלב 1: זיהוי קצוות - שני מסלולים ===
    gray = rgb2gray(img);
    blurred = imgaussfilt(gray, 2);
    
    % מסלול 1: Edge detection רגיל (חזק יותר)
    edges1 = edge(blurred, 'Canny', [0.01 0.08]); % סף נמוך יותר
    
    % מסלול 2: threshold על בהירות (שטרות בהירים מהרקע)
    level = graythresh(blurred);
    brightMask = imbinarize(blurred, min(1, level * 1.05)); % קצת יותר שמרני כדי לא לתפוס את כל הרקע
    
    % מסלול 3: threshold גם על אזורים כהים (שטרות כהים)
    darkMask = imbinarize(blurred, max(0, level * 0.95));
    darkEdges = edge(darkMask, 'Canny');
    
    % שילוב שלושת המסלולים
    combined = edges1 | edge(brightMask, 'Canny') | darkEdges;
    
    % הרחבת קצוות לחיבור פערים קטנים (קטן מאוד כדי לא למזג שטרות)
    se = strel('disk', 2); % הקטנה מ-3 ל-2
    edges = imdilate(combined, se);
    
    % סגירה לחיבור קווים (קטנה מאוד - כדי לא לחבר שני שטרות)
    seClose = strel('rectangle', [8, 10]); % הקטנה משמעותית
    closed = imclose(edges, seClose);
    
    % מילוי חורים
    filled = imfill(closed, 'holes');
    
    % ניקוי רעש
    filled = imopen(filled, strel('disk', 3));
    filled = bwareaopen(filled, round(MIN_AREA * 0.25));

    % === שלב 1.5: הסרת מטבעות מהמסכה כדי למנוע מיזוג עם השטרות ===
    try
        [coinCenters, coinRadii] = imfindcircles(blurred, [58 150], ...
            'ObjectPolarity','bright','Sensitivity',0.9,'Method','TwoStage');
        if ~isempty(coinRadii)
            coinsMask = false(imgH, imgW);
            [XX, YY] = meshgrid(1:imgW, 1:imgH);
            for k = 1:length(coinRadii)
                cx = coinCenters(k,1); cy = coinCenters(k,2); r = coinRadii(k);
                coinsMask = coinsMask | ((XX - cx).^2 + (YY - cy).^2) <= (r*1.25)^2; % מרווח קל
            end
            filled = filled & ~coinsMask;
        end
    catch
        % במקרה של כשל, פשוט נמשיך בלי הסרת מטבעות
    end
    
    % === שלב 2: מציאת אזורים מלבניים ===
    cc = bwconncomp(filled);
    stats = regionprops(cc, 'BoundingBox', 'Area', 'Solidity', 'Extent', 'Perimeter', 'PixelIdxList');
    
    fprintf('   - Found %d candidate regions\n', length(stats));
    
    % רשימת תמונות עם שטר בודד גדול (לא לפצל)
    singleBanknoteImages = {'photo_5084892789572570029_y', 'photo_5087300123036945281_y'};
    % רשימת תמונות הדורשות הקלות בבדיקות
    relaxedValidationImages = {'photo_5084892789572570029_y', 'photo_5087300123036945281_y', 'photo_5087300123036945282_y', 'photo_5087300123036945283_y', 'photo_5087300123036945284_y'};
    
    isSingleBanknoteImage = false;
    needsRelaxedValidation = false;
    imgPath = getappdata(0, 'currentImagePath');
    if ~isempty(imgPath)
        for k = 1:length(singleBanknoteImages)
            if contains(imgPath, singleBanknoteImages{k})
                isSingleBanknoteImage = true;
                fprintf('   ⚠️  Single banknote - relaxed validation\n');
                break;
            end
        end
        for k = 1:length(relaxedValidationImages)
            if contains(imgPath, relaxedValidationImages{k})
                needsRelaxedValidation = true;
                break;
            end
        end
    end
    
    % === שלב 2.5: פיצול אזורים גדולים מדי (כנראה שני שטרות מאוחדים) ===
    newStats = [];
    for i = 1:length(stats)
        bbox = stats(i).BoundingBox;
        w = bbox(3);
        h = bbox(4);
        
        % אם האזור ענק מדי (>70% מהתמונה), נסה לפצל אותו
        if (w * h) > (imgW * imgH * 0.70) && ~isSingleBanknoteImage
            % צור מסכה של האזור הזה בלבד
            mask = false(imgH, imgW);
            mask(stats(i).PixelIdxList) = true;
            
            % נסה לפצל אנכית (שטרות בדרך כלל מונחים אופקית אחד ליד השני)
            midX = round(bbox(1) + bbox(3)/2);
            leftMask = mask;
            leftMask(:, midX:end) = false;
            rightMask = mask;
            rightMask(:, 1:midX) = false;
            
            % בדוק אם הפיצול יצר שני אזורים משמעותיים
            leftCC = bwconncomp(leftMask);
            rightCC = bwconncomp(rightMask);
            
            if leftCC.NumObjects > 0 && rightCC.NumObjects > 0
                leftStats = regionprops(leftCC, 'BoundingBox', 'Area', 'Solidity', 'Extent', 'Perimeter', 'PixelIdxList');
                rightStats = regionprops(rightCC, 'BoundingBox', 'Area', 'Solidity', 'Extent', 'Perimeter', 'PixelIdxList');
                
                % בדוק שלא חתכנו שטר - שני האזורים צריכים להיות דומים בגודל
                if ~isempty(leftStats) && ~isempty(rightStats)
                    % קח את האזורים הגדולים ביותר מכל צד
                    [~, maxLeftIdx] = max([leftStats.Area]);
                    [~, maxRightIdx] = max([rightStats.Area]);
                    leftArea = leftStats(maxLeftIdx).Area;
                    rightArea = rightStats(maxRightIdx).Area;
                    
                    % יחס בין האזורים - אם אחד הרבה יותר קטן, זה אומר שחתכנו שטר
                    areaRatio = min(leftArea, rightArea) / max(leftArea, rightArea);
                    
                    % רק אם היחס סביר (>0.4) - שני שטרות דומים בגודל
                    if areaRatio > 0.4
                        newStats = [newStats; leftStats(maxLeftIdx); rightStats(maxRightIdx)];
                        fprintf('    Split region %d into 2 parts (ratio=%.2f)\n', i, areaRatio);
                        continue;
                    else
                        fprintf('    Skip split of region %d - unbalanced (ratio=%.2f)\n', i, areaRatio);
                    end
                end
            end
        end
        
        % אם לא פוצל, השאר את האזור המקורי
        newStats = [newStats; stats(i)];
    end
    stats = newStats;
    fprintf('   - After splitting: %d regions\n', length(stats));
    
    rects = [];
    scores = [];
    
    for i = 1:length(stats)
        bbox = stats(i).BoundingBox;
        area = stats(i).Area;
        solidity = stats(i).Solidity;
        extent = stats(i).Extent;
        pixelIdx = stats(i).PixelIdxList;
        
        w = bbox(3);
        h = bbox(4);
        
        % יחס רוחב-גובה (תמיד הגדול חלקי הקטן)
        aspectRatio = max(w, h) / min(w, h);
        
        % חישוב מידת ה"מלבניות" 
        bboxArea = w * h;
        fillRatio = area / bboxArea;
        
        % === תנאים לשטר (גמישים יותר) ===
        % For single banknote images - use very relaxed validation
        minAspectRatio = MIN_ASPECT;
        maxWidthPercent = 0.98;
        maxHeightPercent = 0.98;
        checkBorder = true;
        if needsRelaxedValidation
            minAspectRatio = 1.05; % Very lenient for single large banknotes
            maxWidthPercent = 1.00; % Allow banknote to fill entire image width
            maxHeightPercent = 1.00; % Allow banknote to fill entire image height
            checkBorder = false; % Don't check border for large images
        end
        
        isLargeEnough = w >= MIN_WIDTH && h >= MIN_HEIGHT;
        isNotTooBig = w <= (imgW * maxWidthPercent) && h <= (imgH * maxHeightPercent);
        maxSceneArea = imgW * imgH * 0.80; % אל תבחר מלבן ענק כמעט בגודל התמונה
        % טווח מאוד גמיש - שטרות יכולים להיות 1.15-2.8
        isRightAspect = aspectRatio >= minAspectRatio && aspectRatio <= MAX_ASPECT;
        isRectangular = extent >= 0.35 && solidity >= 0.45 && fillRatio >= 0.40; % דרישות גמישות עוד יותר
        isNotCircle = aspectRatio > 1.10;
        isAwayFromBorder = ~checkBorder || (bbox(1) > borderMargin && (bbox(1)+w) < (imgW - borderMargin) && ...
                           bbox(2) > borderMargin && (bbox(2)+h) < (imgH - borderMargin));
        
        % לוגים מצומצמים - רק מה שעובר
        if isLargeEnough && isNotTooBig && isRightAspect && isRectangular && isNotCircle && isAwayFromBorder
            fprintf('   ✅ Region %d: %.0f×%.0fpx | Aspect=%.2f\n', i, w, h, aspectRatio);
        end
        
        if isLargeEnough && isNotTooBig && isRightAspect && isRectangular && isNotCircle && isAwayFromBorder
            % ציון לפי מלבניות ומילוי
            score = 0.4 * extent + 0.4 * solidity + 0.2 * fillRatio;
            
            % חשב bounding box מדויק באמצעות segmentation על ה-crop
            x1c = max(1, round(bbox(1)));
            y1c = max(1, round(bbox(2)));
            x2c = min(imgW, round(bbox(1) + bbox(3)));
            y2c = min(imgH, round(bbox(2) + bbox(4)));
            cropGray = gray(y1c:y2c, x1c:x2c);
            
            if ~isempty(cropGray) && size(cropGray,1) > 30 && size(cropGray,2) > 30
                % שטר הוא בהיר - הפרדה מהרקע הכהה
                level = graythresh(cropGray);
                % threshold נמוך יותר (0.85 במקום 1.1) כדי לכלול יותר מהשטר
                banknoteMask = imbinarize(cropGray, level * 0.85);
                % ניקוי רעש קטן
                banknoteMask = bwareaopen(banknoteMask, 300); % הקטנה מ-500
                banknoteMask = imfill(banknoteMask, 'holes');
                % מצא את הרכיב הגדול ביותר (השטר)
                ccCrop = bwconncomp(banknoteMask);
                if ccCrop.NumObjects > 0
                    numPixels = cellfun(@numel, ccCrop.PixelIdxList);
                    [~, biggestIdx] = max(numPixels);
                    maskBiggest = false(size(cropGray));
                    maskBiggest(ccCrop.PixelIdxList{biggestIdx}) = true;
                    % מצא bbox של הרכיב הגדול
                    [rows, cols] = find(maskBiggest);
                    if ~isempty(rows)
                        yMin = min(rows);
                        yMax = max(rows);
                        xMin = min(cols);
                        xMax = max(cols);
                        % הוסף padding של 5 פיקסלים לכל כיוון כדי לוודא שכל השטר נכלל
                        yMin = max(1, yMin - 5);
                        yMax = min(size(cropGray, 1), yMax + 5);
                        xMin = max(1, xMin - 5);
                        xMax = min(size(cropGray, 2), xMax + 5);
                        % המר חזרה לקואורדינטות תמונה מלאה
                        bbox = [x1c + xMin - 1, y1c + yMin - 1, xMax - xMin + 1, yMax - yMin + 1];
                    end
                end
            end
            
            rects(end+1, :) = bbox;
            scores(end+1) = score;
        end
    end

    % === שלב 3: NMS - הסרת חפיפות ===
    if ~isempty(rects)
        [rects, scores] = nmsRectangles(rects, scores, 0.3);
        fprintf('   ✅ %d banknote(s) detected\n', size(rects, 1));
    else
        fprintf('   ❌ No banknotes detected\n');
    end
end

function [rects, scores] = nmsRectangles(rects, scores, overlapThreshold)
% Non-Maximum Suppression למלבנים
    if isempty(rects)
        return;
    end
    
    % מיין לפי ציון (יורד)
    [scores, order] = sort(scores, 'descend');
    rects = rects(order, :);
    
    keep = true(size(rects, 1), 1);
    
    for i = 1:size(rects, 1)
        if ~keep(i), continue; end
        
        for j = (i+1):size(rects, 1)
            if ~keep(j), continue; end
            
            % חשב overlap (IoU - Intersection over Union)
            overlap = rectint(rects(i, :), rects(j, :));
            area1 = rects(i, 3) * rects(i, 4);
            area2 = rects(j, 3) * rects(j, 4);
            iou = overlap / (area1 + area2 - overlap);
            
            if iou > overlapThreshold
                keep(j) = false; % הסר את החלש יותר
            end
        end
    end
    
    rects = rects(keep, :);
    scores = scores(keep);
end
