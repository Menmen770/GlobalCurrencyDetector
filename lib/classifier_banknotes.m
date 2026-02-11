function detectedBanknotes = classifier_banknotes(img, rects, refDB, banknoteDB)
% CLASSIFIER_BANKNOTES - מסווג שטרות שזוהו לפי גודל, צבע, ו-SURF
% מחזיר struct עם גם ה-BBox של כל שטר שזוהה בהצלחה
    
    numBanknotes = size(rects, 1);
    detectedBanknotes = struct('Currency', {}, 'Name', {}, 'Value', {}, 'Method', {}, 'BBox', {});
    
    fprintf('\n🔍 [Banknote Classification]\n');
    drawnow;
    
    if numBanknotes == 0
        return;
    end
    
    for i = 1:numBanknotes
        bbox = rects(i, :); % [x, y, width, height]
        
        % גזור את אזור השטר
        x1 = max(1, round(bbox(1)));
        y1 = max(1, round(bbox(2)));
        x2 = min(size(img, 2), round(bbox(1) + bbox(3)));
        y2 = min(size(img, 1), round(bbox(2) + bbox(4)));
        crop = img(y1:y2, x1:x2, :);
        
        if isempty(crop) || size(crop, 1) < 10 || size(crop, 2) < 10
            continue;
        end
        
        grayCrop = rgb2gray(crop);
        % הכן גם גרסה מסובבת 180 מעלות לזיהוי שטרות הפוכים
        grayCropRotated = rot90(grayCrop, 2);
        
        % חלץ צבע דומיננטי מהשטר
        [dominantHue, ~] = extractDominantColorHSV(crop);
        
        fprintf('   Region %d: Detected Hue=%.0f°\n', i, dominantHue);
        
        % מצא מועמדים - כל השטרות הם מועמדים! (לא מסננים לפי גודל)
        candidates = 1:length(banknoteDB);
        
        if isempty(candidates)
            % 🚫 אין מועמד טוב - לא מנחשים! מדלגים על האזור הזה
            fprintf('  ⚠ Region %d: %.0f×%.0fpx → No match (skipped, no guessing)\n', ...
                    i, width, height);
            continue;  % דלג לאיטרציה הבאה, לא מוסיף לתוצאות
        else
            % === שלב 1: חשב SURF לכל המועמדים (בשני הכיוונים!) ===
            surfMatches = zeros(1, length(candidates));
            for c = 1:length(candidates)
                bn = banknoteDB(candidates(c));
                if ~isempty(refDB)
                    % נסה את הכיוון הרגיל והמסובב, קח את המקסימום
                    matchNormal = matchBanknoteSURF(grayCrop, refDB, bn.Name);
                    matchRotated = matchBanknoteSURF(grayCropRotated, refDB, bn.Name);
                    surfMatches(c) = max(matchNormal, matchRotated);
                end
            end
            
            % מצא את המקסימום לנרמול יחסי
            maxSurfMatches = max(surfMatches);
            
            % === שלב 2: חשב ציון משולב - SURF + צבע ===
            scores = zeros(1, length(candidates));
            
            for c = 1:length(candidates)
                bnIdx = candidates(c);
                bn = banknoteDB(bnIdx);
                
                % ציון SURF יחסי
                if maxSurfMatches > 10
                    surfScore = surfMatches(c) / maxSurfMatches;
                else
                    surfScore = 0;
                end
                
                % ציון צבע - השוואת Hue
                expectedHue = bn.DominantColor(1);  % Hue מהגדרת השטר
                colorScore = calculateHueScore(dominantHue, expectedHue);
                
                % ציון סופי: 70% SURF + 30% צבע (העלאת משקל SURF לדיוק)
                scores(c) = 0.70 * surfScore + 0.30 * colorScore;
            end
            
            % בחר את המטבע עם הציון הגבוה ביותר
            [maxScore, bestIdx] = max(scores);
            
            % 🚫 אם הציון נמוך מדי - לא מזהים
            if maxScore < 0.35
                continue;
            end
            
            finalBanknote = banknoteDB(candidates(bestIdx));
            method = sprintf('Score: %.2f', maxScore);
        end
        
        % הוסף לרשימת הזיהויים (משתמש ב-end+1 כי אולי דילגנו על כמה)
        idx = length(detectedBanknotes) + 1;
        detectedBanknotes(idx).Currency = finalBanknote.Currency;
        detectedBanknotes(idx).Name = finalBanknote.Name;
        detectedBanknotes(idx).Value = finalBanknote.Value;
        detectedBanknotes(idx).Method = method;
        detectedBanknotes(idx).BBox = bbox;  % שמור את ה-BBox
        
        fprintf('✓ Banknote %d | %.0f×%.0fpx | %s | %s\n', ...
            idx, bbox(3), bbox(4), finalBanknote.Name, method);
    end
    
    fprintf('\n');
end

function [dominantHue, dominantSat] = extractDominantColorHSV(img)
% מחלץ צבע דומיננטי מהשטר בפורמט HSV (יותר עמיד לתאורה)
    [h, w, ~] = size(img);
    
    % קח אזור מרכזי (50% מהשטר)
    y1 = round(h * 0.25);
    y2 = round(h * 0.75);
    x1 = round(w * 0.25);
    x2 = round(w * 0.75);
    
    center = img(y1:y2, x1:x2, :);
    
    % המר ל-HSV
    hsvImg = rgb2hsv(center);
    H = hsvImg(:,:,1);
    S = hsvImg(:,:,2);
    V = hsvImg(:,:,3);
    
    % קח רק פיקסלים עם saturation מספיקה (לא אפורים) וערך מספיק (לא כהים)
    validMask = (S > 0.1) & (V > 0.15);
    
    if sum(validMask(:)) > 100
        % ממוצע Hue של פיקסלים צבעוניים - המרה למעלות
        avgHue = mean(H(validMask)) * 360;
        avgSat = mean(S(validMask)) * 100;
    else
        avgHue = mean(H(:)) * 360;
        avgSat = mean(S(:)) * 100;
    end
    
    dominantHue = avgHue;
    dominantSat = avgSat;
end

function score = calculateHueScore(detectedHue, expectedHue)
% מחשב ציון התאמה בין שני ערכי Hue (0-360)
% Hue הוא מעגלי, אז צריך לטפל במעבר בין 360 ל-0
    
    % חשב הפרש מעגלי
    diff = abs(detectedHue - expectedHue);
    if diff > 180
        diff = 360 - diff;
    end
    
    % המר להפרש לציון (0-1)
    % הפרש של 0 = ציון 1, הפרש של 60+ = ציון 0
    maxAllowedDiff = 60;  % הפרש מקסימלי סביר
    score = max(0, 1 - diff / maxAllowedDiff);
end

function matchCount = matchBanknoteSURF(img, refDB, targetBanknoteName)
% SURF matching - מחזיר מספר התאמות מול שטר ספציפי
    matchCount = 0;
    try
        pts = detectSURFFeatures(img, 'MetricThreshold', 200);
        if pts.Count == 0
            return;
        end
        [feats, ~] = extractFeatures(img, pts);
        
        % חפש את הרפרנס של השטר המבוקש
        for k = 1:length(refDB)
            if strcmp(refDB(k).Name, targetBanknoteName)
                pairs = matchFeatures(feats, refDB(k).Features, 'MaxRatio', 0.8, 'Unique', true);
                matchCount = size(pairs, 1);
                return;
            end
        end
    catch
        % SURF יכול להיכשל
    end
end
