/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250808@Danny
	DB: DBCUST.bodb_Licensee
	Task: HOTDOG - offer Promotion Prize [#230452]
	Description: Insert Into LA_InvoiceItemType new  items
*/
USE bodb_Licensee
GO



DECLARE @PLTLive_Contrib INT = 69

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PLTLive_Contrib)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PLTLive_Contrib, 1, 'Income', 1, '', N'Return Playtech Live Contribution')
END

DECLARE @PLTLive_JP INT = 70

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PLTLive_JP)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PLTLive_JP, -1, 'Expense', -1, '', N'Deduct Playtech Live Jackpot Prize')
END



