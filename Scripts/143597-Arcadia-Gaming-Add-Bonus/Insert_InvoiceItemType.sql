/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201028@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Arcadia-Gaming-Add-Bonus [#FeatureID 143597]
	Description: Insert Into LA_InvoiceItemType record: ArcadiaGaming_Bonus
*/
USE bodb_Licensee
GO

DECLARE @ArcadiaGaming_Bonus INT = 33

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @ArcadiaGaming_Bonus)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@ArcadiaGaming_Bonus, -1, 'Expense', -1, '', N'Deduct Arcadia Gaming bonus amount for Mini Games')
END