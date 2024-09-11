/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240911@Danny
	DB: DBCUST.bodb_Licensee
	Task: FACHAI - offer Promotion Prize [#209902]
	Description: Insert Into LA_InvoiceItemType record: Deduct Vgaming Promotion
*/
USE bodb_Licensee
GO

DECLARE @FAC_Prize INT = 59

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @FAC_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@FAC_Prize, -1, 'Expense', -1, '', N'Deduct FA CHAI Promotion')
END



