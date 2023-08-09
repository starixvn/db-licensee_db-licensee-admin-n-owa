/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20231004@Danny
	DB: DBCUST.bodb_Licensee
	Task: SB - Parlay Boost integration [#191662]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Deduct PG Promotion
*/
USE bodb_Licensee
GO

DECLARE @SB_ParlayBoostBonus INT = 51

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SB_ParlayBoostBonus)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SB_ParlayBoostBonus, -1, 'Expense', -1, '', N'Deduct Parlay Boost Bonus')
END

