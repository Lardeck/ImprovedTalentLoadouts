local addonName, TalentLoadouts = ...

ImprovedTalentLoadoutsCreateDialogMixin = {};

function ImprovedTalentLoadoutsCreateDialogMixin:OnLoad()
	self.exclusive = true;
	self.AcceptButton:SetOnClickHandler(GenerateClosure(self.OnAccept, self));
	self.CancelButton:SetOnClickHandler(GenerateClosure(self.OnCancel, self));
	ImprovedTalentLoadoutsDialogMixin.OnLoad(self);
end

function ImprovedTalentLoadoutsCreateDialogMixin:UpdateAcceptButtonEnabledState()
	local nameTextFilled = self.NameControl:HasText();
	self.AcceptButton:SetEnabled(nameTextFilled);
end

function ImprovedTalentLoadoutsCreateDialogMixin:OnTextChanged()
	self:UpdateAcceptButtonEnabledState();
end

function ImprovedTalentLoadoutsCreateDialogMixin:OnAccept()
	if self.AcceptButton:IsEnabled() then
		local loadoutName = self.NameControl:GetText();

		StaticPopupSpecial_Hide(self);

		self.acceptCallback(loadoutName);
	end
end

function ImprovedTalentLoadoutsCreateDialogMixin:OnCancel()
	StaticPopupSpecial_Hide(self);
end

function ImprovedTalentLoadoutsCreateDialogMixin:ShowDialog()
	StaticPopupSpecial_Show(self);
end

ImprovedTalentLoadoutsCreateDialogNameControlMixin = {};

function ImprovedTalentLoadoutsCreateDialogNameControlMixin:OnShow()
	ImprovedTalentLoadoutsDialogNameControlMixin.OnShow(self);
	self:GetEditBox():SetFocus();
end

function ImprovedTalentLoadoutsCreateDialogNameControlMixin:OnEnterPressed()
	self:GetParent():OnAccept();
end

function ImprovedTalentLoadoutsCreateDialogNameControlMixin:OnEscapePressed()
	self:GetParent():OnCancel();
end

function ImprovedTalentLoadoutsCreateDialogNameControlMixin:OnTextChanged()
	self:GetParent():OnTextChanged();
end