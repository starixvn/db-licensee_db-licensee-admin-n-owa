/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240131@Danny
	DB: DBCUST.bodb_Licensee
	Task: AGC - Jackpot prize promotion integration [#197268]
	Description: Insert Into LA_InvoiceItemType record: 

		1. Deduct AG Casino Promotion
		2. Return AG Casino Contribution
		3. Deduct AG Casino Jackpot Prize
*/
USE bodb_Licensee
GO

DECLARE @AGC_PromotionPrize INT = 54

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @AGC_PromotionPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@AGC_PromotionPrize, -1, 'Expense', -1, '', N'Deduct AG Casino Promotion')
END

DECLARE @AGC_Contribution INT = 55

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @AGC_Contribution)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@AGC_Contribution, 1, 'Income', 1, '', N'Return AG Casino Contribution')
END

DECLARE @AGC_JackpotPrize INT = 56

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @AGC_JackpotPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@AGC_JackpotPrize, -1, 'Expense', -1, '', N'Deduct AG Casino Jackpot Prize')
END

