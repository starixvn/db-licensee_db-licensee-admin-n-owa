/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20220110@Danny
	DB: DBCUST.bodb_Licensee
	Task: SG - Jackpot prize integration [#167089]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Return SG Contribution
		2. Deduct SG Jackpot Prize
*/
USE bodb_Licensee
GO

DECLARE @SG_Contribution INT = 41

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SG_Contribution)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SG_Contribution, 1, 'Income', 1, '', N'Return SG Contribution')
END

DECLARE @SG_JackpotPrize INT = 42

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SG_JackpotPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SG_JackpotPrize, -1, 'Expense', -1, '', N'Deduct SG Jackpot Prize')
END


