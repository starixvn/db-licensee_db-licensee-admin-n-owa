/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20221221@Danny
	DB: DBCUST.bodb_Licensee
	Task: TIP - Player tips [#176986]
	Description: Insert Into LA_InvoiceItemType record: Player tips
*/
USE bodb_Licensee
GO

DECLARE @Tips INT = 48

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @Tips)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@Tips, 1, 'Income', 1, 'Combine with 1', N'Player Tips')
END
