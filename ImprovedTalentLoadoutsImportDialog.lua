local addonName, TalentLoadouts = ...

ImprovedTalentLoadoutsDialogMixin = {};

function ImprovedTalentLoadoutsDialogMixin:OnLoad()
	self.Title:SetText(self.titleText);
end

ImprovedTalentLoadoutsDialogInputControlMixin = {};

function ImprovedTalentLoadoutsDialogInputControlMixin:OnLoad()
	local editBox = self:GetEditBox();
	editBox:SetScript("OnTextChanged", GenerateClosure(self.OnTextChanged, self));
	editBox:SetScript("OnEnterPressed", GenerateClosure(self.OnEnterPressed, self));
	editBox:SetScript("OnEscapePressed", GenerateClosure(self.OnEscapePressed, self));
	self.Label:SetText(self.labelText);
end

function ImprovedTalentLoadoutsDialogInputControlMixin:OnShow()
	self:GetEditBox():SetText("");
end

function ImprovedTalentLoadoutsDialogInputControlMixin:GetText()
	return self:GetEditBox():GetText();
end

function ImprovedTalentLoadoutsDialogInputControlMixin:SetText(text)
	return self:GetEditBox():SetText(text);
end

function ImprovedTalentLoadoutsDialogInputControlMixin:HasText()
	return UserEditBoxNonEmpty(self:GetEditBox());
end

function ImprovedTalentLoadoutsDialogInputControlMixin:OnEnterPressed()
end

function ImprovedTalentLoadoutsDialogInputControlMixin:OnEscapePressed()
end

function ImprovedTalentLoadoutsDialogInputControlMixin:OnTextChanged()
end

function ImprovedTalentLoadoutsDialogInputControlMixin:GetEditBox()
end

ImprovedTalentLoadoutsDialogNameControlMixin = CreateFromMixins(ImprovedTalentLoadoutsDialogInputControlMixin);

function ImprovedTalentLoadoutsDialogNameControlMixin:GetEditBox()
	return self.EditBox;
end

ImprovedTalentLoadoutsImportDialogMixin = {}

function ImprovedTalentLoadoutsImportDialogMixin:OnLoad()
	self.exclusive = true;
	self.AcceptButton:SetOnClickHandler(GenerateClosure(self.OnAccept, self));
	self.CancelButton:SetOnClickHandler(GenerateClosure(self.OnCancel, self));
	ImprovedTalentLoadoutsDialogMixin.OnLoad(self);

	self.NameControl:GetEditBox():SetAutoFocus(false);
	self.ImportControl:GetEditBox():SetAutoFocus(true);
end

function ImprovedTalentLoadoutsImportDialogMixin:OnHide()

end

function ImprovedTalentLoadoutsImportDialogMixin:OnCancel()
	StaticPopupSpecial_Hide(self);
end

function ImprovedTalentLoadoutsImportDialogMixin:OnAccept()
	if self.AcceptButton:IsEnabled() then
		local importString = self.ImportControl:GetText();
		local loadoutName = self.NameControl:GetText();

        local fakeConfigID
        local treeType = self.treeType
        local categoryInfo = self.categoryInfo

        if not treeType or treeType == 1 then
            fakeConfigID = TalentLoadouts:ImportLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
        elseif treeType == 2 then
            loadoutName = string.format("[C] %s", loadoutName)
            fakeConfigID = TalentLoadouts:ImportClassLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
        elseif treeType == 3 then
            loadoutName = string.format("[S] %s", loadoutName)
            fakeConfigID = TalentLoadouts:ImportSpecLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
        end
		
        if fakeConfigID then
			StaticPopupSpecial_Hide(self);

            if IsShiftKeyDown() then
                TalentLoadouts:LoadLoadoutByConfigID(fakeConfigID, self.categoryInfo)
            end
        end
	end
end

function ImprovedTalentLoadoutsImportDialogMixin:UpdateAcceptButtonEnabledState()
	local importTextFilled = self.ImportControl:HasText();
	local nameTextFilled = self.NameControl:HasText();
	self.AcceptButton:SetEnabled(importTextFilled and nameTextFilled);
end

function ImprovedTalentLoadoutsImportDialogMixin:OnTextChanged()
	self:UpdateAcceptButtonEnabledState();
end

function ImprovedTalentLoadoutsImportDialogMixin:ShowDialog(treeType, categoryInfo)
    self.treeType = treeType
    self.categoryInfo = categoryInfo

	StaticPopupSpecial_Show(self);
end


ImprovedTalentLoadoutsImportDialogImportControlMixin = CreateFromMixins(ImprovedTalentLoadoutsDialogInputControlMixin);

function ImprovedTalentLoadoutsImportDialogImportControlMixin:OnShow()
	ImprovedTalentLoadoutsDialogInputControlMixin.OnShow(self);
end

function ImprovedTalentLoadoutsImportDialogImportControlMixin:OnEnterPressed()
	self:GetParent():OnAccept();
end

function ImprovedTalentLoadoutsImportDialogImportControlMixin:OnEscapePressed()
	self:GetParent():OnCancel();
end

function ImprovedTalentLoadoutsImportDialogImportControlMixin:OnTextChanged()
	self:GetParent():OnTextChanged();
	InputScrollFrame_OnTextChanged(self.InputContainer.EditBox);
end

function ImprovedTalentLoadoutsImportDialogImportControlMixin:GetEditBox()
	return self.InputContainer.EditBox;
end

ImprovedTalentLoadoutsImportDialogNameControlMixin = {}

function ImprovedTalentLoadoutsImportDialogNameControlMixin:OnEnterPressed()
	self:GetParent():OnAccept();
end

function ImprovedTalentLoadoutsImportDialogNameControlMixin:OnEscapePressed()
	self:GetParent():OnCancel();
end

function ImprovedTalentLoadoutsImportDialogNameControlMixin:OnTextChanged()
	self:GetParent():OnTextChanged();
end
