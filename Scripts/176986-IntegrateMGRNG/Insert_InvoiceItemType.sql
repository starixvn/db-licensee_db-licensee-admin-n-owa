/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20221024@Danny
	DB: DBCUST.bodb_Licensee
	Task: MGRNG - offer Tournament Prize [#176986]
	Description: Insert Into LA_InvoiceItemType record: MGRNG Tournament Prize
*/
USE bodb_Licensee
GO

DECLARE @MGRNG_Prize INT = 47

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @MGRNG_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@MGRNG_Prize, -1, 'Expense', -1, '', N'Deduct MG-RNG Promotion')
END
