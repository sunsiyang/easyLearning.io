require('torch')

local jaccardOverlap = function(b1, b2)
    local xmin = math.min(b1.xmin, b2.xmin)
    local ymin = math.min(b1.ymin, b2.ymin)
    local xmax = math.max(b1.xmax, b2.xmax)
    local ymax = math.max(b1.ymax, b2.ymax)

    local w1 = b1.xmax - b1.xmin
    local h1 = b1.ymax - b1.ymin
    local w2 = b2.xmax - b2.xmin
    local h2 = b2.ymax - b2.ymin
  
    -- no overlap
    if ( (xmax - xmin) >= ( w1 + w2) or
        (ymax - ymin) >= ( h1 + h2) ) then
        return 0
    end
    
    local andw = w1 + w2 - (xmax - xmin)
    local andh = h1 + h2 - (ymax - ymin)

    local andArea = andw * andh
    local orArea = w1 * h1 + w2*h2 - andArea
    
    return andArea / orArea
end
    
local boxSampling = function(modelInfo, imageWidth, imageHeight, labels) 
    local _ = modelInfo.getSize(imageWidth, imageHeight)
    local lastWidth = _[1]
    local lastHeight = _[2]
    
    local cellWidth = imageWidth / lastWidth
    local cellHeight = imageHeight / lastHeight
    
    -- build all pred boxes
    local predBoxes = {}
    for i = 1, #modelInfo.boxes do
        local wid = lastWidth - (modelInfo.boxes[i][1] - 1)
        local hei = lastHeight - (modelInfo.boxes[i][2] - 1)
        
        for h = 1, hei do
            for w = 1, wid do
                local box = {}
                box.score = 0.0
                box.label = -1
                box.xmin = (w-1) * cellWidth 
                box.ymin = (h-1) * cellHeight 
                box.xmax = (w + modelInfo.boxes[i][1] - 1) * cellWidth
                box.ymax = (h + modelInfo.boxes[i][2] - 1) * cellHeight
                
                table.insert(predBoxes, box)
                predBoxes["_" .. i .. "_" .. h .. "_" .. w] = box
            end
        end
    end
   
    if ( labels == nil) then
        return predBoxes
    end

    -- find best match between labels (groud truth) and predBoxes
    local matchMap = torch.zeros(#predBoxes, #labels) - 1
    for i = 1, #predBoxes do
        for j = 1, #labels do
            local overlap = jaccardOverlap(predBoxes[i], labels[j]) 
            if ( overlap > 0.0001 ) then
                matchMap[i][j] = overlap
            end
        end
    end
 
    local positiveNumber = 0
    local negativeNumber = 0
    
    -- best match from bidirection
    for i = 1, #labels do
        local tempMap = matchMap:reshape(#predBoxes * #labels)
        local score, _ = tempMap:max(1);
       
        local p = math.floor((_[1] - 1) / #labels) + 1
        local l = _[1] - (p - 1) * #labels
            
        matchMap[p] = -1
        predBoxes[p].score = score[1]
        predBoxes[p].label = l
        positiveNumber = positiveNumber + 1
    end
    
    -- select rest best match > threshold as postive
    for i = 1, #predBoxes do
        local score, _ = matchMap[i]:max(1)
        if ( score[1] > 0.50 ) then
            predBoxes[i].score = score[1]
            predBoxes[i].label = _[1];
            matchMap[i] = -1
            positiveNumber = positiveNumber + 1
        end
    end
   
    -- do negative sampling
    local tempMap = matchMap:reshape(#predBoxes * #labels)
    local score, _ = tempMap:sort(true)
    for i = 1, positiveNumber * 4 do
        if ( i > #predBoxes * #labels) then
            break
        end
        
        local p = math.floor( (_[i] - 1) / #labels) + 1
        predBoxes[p].score = score[i]
        predBoxes[p].label = 0
        negativeNumber = negativeNumber + 1
    end

    return predBoxes, positiveNumber, negativeNumber
end

return boxSampling
