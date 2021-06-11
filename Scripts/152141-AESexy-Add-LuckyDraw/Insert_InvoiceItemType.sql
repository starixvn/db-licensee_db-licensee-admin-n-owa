/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210611@Danny
	DB: DBCUST.bodb_Licensee
	Task: AE Sexy - Support Lucky Draw [#152141]
	Description: Insert Into LA_InvoiceItemType record: ArcadiaGaming_Bonus
*/
USE bodb_Licensee
GO

DECLARE @AESexyLuckyDraw INT = 37

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @AESexyLuckyDraw)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@AESexyLuckyDraw, -1, 'Expense', -1, '', N'Deduct AE Sexy Lucky Draw')
END
