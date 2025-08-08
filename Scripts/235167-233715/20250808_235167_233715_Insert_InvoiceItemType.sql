/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250808@Danny
	DB: DBCUST.bodb_Licensee
	Task: HOTDOG - offer Promotion Prize #235167 #233715]
	Description: Insert Into LA_InvoiceItemType new  items
*/
USE bodb_Licensee
GO

DECLARE @VS2_Prize INT = 66

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @VS2_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@VS2_Prize, -1, 'Expense', -1, '', N'Deduct Virtual Sport Promotion')
END


DECLARE @PLT_Contrib INT = 67

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PLT_Contrib)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PLT_Contrib, 1, 'Income', 1, '', N'Return Playtech Contribution')
END

DECLARE @PLT_JP INT = 68

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PLT_JP)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PLT_JP, -1, 'Expense', -1, '', N'Deduct Playtech Jackpot Prize')
END





