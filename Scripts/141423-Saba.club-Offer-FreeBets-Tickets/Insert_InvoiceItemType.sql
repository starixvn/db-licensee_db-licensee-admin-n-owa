/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201204@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Saba.club - Offer Freebet tickets [#141423]
	Description: Insert Into LA_InvoiceItemType record: Deduct Saba.club Free Bets amount
*/
USE bodb_Licensee
GO

DECLARE @Sabaclub_FreeBets INT = 34

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @Sabaclub_FreeBets)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@Sabaclub_FreeBets, -1, 'Expense', -1, '', N'Deduct Saba.club Free Bets amount')
END