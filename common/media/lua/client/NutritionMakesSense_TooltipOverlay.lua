NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_TooltipLogic"

local TooltipOverlay = NutritionMakesSense.TooltipOverlay or {}
NutritionMakesSense.TooltipOverlay = TooltipOverlay

if TooltipOverlay._installed then
    return TooltipOverlay
end
TooltipOverlay._installed = true

local TooltipLogic = NutritionMakesSense.TooltipLogic

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end

    return result
end

local function getTooltipPadding(tooltip)
    local padLeft = tonumber(tooltip and tooltip.padLeft)
    local padRight = tonumber(tooltip and tooltip.padRight)
    local padTop = tonumber(tooltip and tooltip.padTop)
    local padBottom = tonumber(tooltip and tooltip.padBottom)
    if padLeft and padRight and padTop and padBottom then
        return padLeft, padRight, padTop, padBottom
    end

    local font = tooltip and safeCall(tooltip, "getFont") or nil
    local textManager = _G.TextManager and TextManager.instance or nil
    local charWidth = tonumber(textManager and font and safeCall(textManager, "MeasureStringX", font, "1") or nil) or 5
    if charWidth < 1 then
        charWidth = 5
    end
    charWidth = charWidth + 2
    local verticalPad = math.floor(charWidth / 2)
    if verticalPad < 1 then
        verticalPad = 2
    end
    return charWidth + 1, charWidth, verticalPad, verticalPad
end

local function renderTooltipLayoutForItem(item, tooltip)
    if not item or not tooltip then
        return false
    end

    local doTooltipEmbedded = item.DoTooltipEmbedded
    if type(doTooltipEmbedded) ~= "function" then
        return false
    end

    local layout = safeCall(tooltip, "beginLayout")
    if not layout then
        return false
    end

    local ok = pcall(function()
        safeCall(layout, "setMinLabelWidth", 80)
        safeCall(layout, "setMinValueWidth", 80)
        item:DoTooltipEmbedded(tooltip, layout, 0)
        TooltipLogic.appendDescriptorRowsToLayout(layout, item)

        local padLeft, _, padTop, padBottom = getTooltipPadding(tooltip)
        local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
        local top = padTop + lineSpacing + 5
        local height = tonumber(safeCall(layout, "render", padLeft, top, tooltip)) or top
        safeCall(tooltip, "endLayout", layout)

        local width = tonumber(safeCall(tooltip, "getWidth")) or 0
        if width < 150 then
            width = 150
        end

        safeCall(tooltip, "setHeight", math.floor(height + padBottom))
        safeCall(tooltip, "setWidth", math.floor(width))
    end)

    if not ok then
        pcall(function()
            safeCall(tooltip, "endLayout", layout)
        end)
        return false
    end

    return true
end

function TooltipOverlay.renderItemTooltip(item, tooltip)
    if item then
        if not renderTooltipLayoutForItem(item, tooltip) then
            item:DoTooltip(tooltip)
            TooltipLogic.appendDescriptorsToTooltip(tooltip, item)
        end
    end
end

local function patchInventoryTooltip()
    if not ISToolTipInv or TooltipOverlay._inventoryTooltipPatched then
        return
    end

    TooltipOverlay._inventoryTooltipPatched = true

    function ISToolTipInv:render()
        if not ISContextMenu.instance or not ISContextMenu.instance.visibleCheck then
            local mx = getMouseX() + 24
            local my = getMouseY() + 24
            if not self.followMouse then
                mx = self:getX()
                my = self:getY()
                if self.anchorBottomLeft then
                    mx = self.anchorBottomLeft.x
                    my = self.anchorBottomLeft.y
                end
            end

            local PADX = 0

            self.tooltip:setX(mx + PADX)
            self.tooltip:setY(my)

            self.tooltip:setWidth(50)
            self.tooltip:setMeasureOnly(true)
            TooltipOverlay.renderItemTooltip(self.item, self.tooltip)
            self.tooltip:setMeasureOnly(false)

            local myCore = getCore()
            local maxX = myCore:getScreenWidth()
            local maxY = myCore:getScreenHeight()

            local tw = self.tooltip:getWidth()
            local th = self.tooltip:getHeight()

            self.tooltip:setX(math.max(0, math.min(mx + PADX, maxX - tw - 1)))
            if not self.followMouse and self.anchorBottomLeft then
                self.tooltip:setY(math.max(0, math.min(my - th, maxY - th - 1)))
            else
                self.tooltip:setY(math.max(0, math.min(my, maxY - th - 1)))
            end

            if self.contextMenu and self.contextMenu.joyfocus then
                local playerNum = self.contextMenu.player
                self.tooltip:setX(getPlayerScreenLeft(playerNum) + 60)
                self.tooltip:setY(getPlayerScreenTop(playerNum) + 60)
            elseif self.contextMenu and self.contextMenu.currentOptionRect then
                if self.contextMenu.currentOptionRect.height > 32 then
                    self:setY(my + self.contextMenu.currentOptionRect.height)
                end
                self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
            end

            self:setX(self.tooltip:getX() - PADX)
            self:setY(self.tooltip:getY())
            self:setWidth(tw + PADX)
            self:setHeight(th)

            if self.followMouse and (self.contextMenu == nil) then
                self:adjustPositionToAvoidOverlap({ x = mx - 24 * 2, y = my - 24 * 2, width = 24 * 2, height = 24 * 2 })
            end

            self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
            self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
            TooltipOverlay.renderItemTooltip(self.item, self.tooltip)
        end
    end
end

local function patchItemSlotTooltip()
    if not ISItemSlot or TooltipOverlay._itemSlotTooltipPatched then
        return
    end

    TooltipOverlay._itemSlotTooltipPatched = true
    local originalDrawTooltip = ISItemSlot.drawTooltip

    ISItemSlot.drawTooltip = function(itemSlot, tooltip)
        if originalDrawTooltip then
            originalDrawTooltip(itemSlot, tooltip)
        end

        local item = itemSlot and (itemSlot.resource or itemSlot.storedItem) or nil
        TooltipLogic.appendDescriptorsToTooltip(tooltip, item)
    end
end

local function install()
    patchInventoryTooltip()
    patchItemSlotTooltip()
end

install()

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(install)
end

return TooltipOverlay
