/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210713@Danny
	DB: DBCUST.bodb_Licensee
	Task: Vgaming - Free bets and Jackpot prize integration [#156185]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Return Vgaming Contribution
		2. Deduct Vgaming Jackpot Prize
		3. Deduct Vgaming Free Bets amount
*/
USE bodb_Licensee
GO

DECLARE @VG_FreeBets INT = 38

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @VG_FreeBets)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@VG_FreeBets, -1, 'Expense', -1, '', N'Deduct Vgaming Free Bets amount')
END


DECLARE @VG_JackpotPrize INT = 39

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @VG_JackpotPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@VG_JackpotPrize, -1, 'Expense', -1, '', N'Deduct Vgaming Jackpot Prize')
END


DECLARE @VG_Contribution INT = 40

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @VG_Contribution)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@VG_Contribution, 1, 'Income', 1, '', N'Return Vgaming Contribution')
END