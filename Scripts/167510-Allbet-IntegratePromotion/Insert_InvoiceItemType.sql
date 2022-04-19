/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20220222@Danny
	DB: DBCUST.bodb_Licensee
	Task: Allbet - promotion integration [#167510]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Deduct Allbet Promotion
*/
USE bodb_Licensee
GO

DECLARE @Allbet_Promotion INT = 43

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @Allbet_Promotion)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@Allbet_Promotion, -1, 'Expense', -1, '', N'Deduct Allbet Promotion')
END



