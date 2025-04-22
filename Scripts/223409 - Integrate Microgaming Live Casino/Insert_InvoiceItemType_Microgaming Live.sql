/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250417@Lionel
	DB: DBCUST.bodb_Licensee
	Task: Microgaming Live - offer Promotion Prize #223409]
	Description: Insert Into LA_InvoiceItemType record: Deduct Microgaming Live Promotion
*/
USE bodb_Licensee
GO

DECLARE @MGLC_Prize INT = 64

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @MGLC_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@MGLC_Prize, -1, 'Expense', -1, '', N'Deduct Microgaming Live Promotion')
END