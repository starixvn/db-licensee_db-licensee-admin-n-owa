/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20230608@Danny
	DB: DBCUST.bodb_Licensee
	Task: PG - Promotion prize integration [#188997]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Deduct PG Promotion
*/
USE bodb_Licensee
GO

DECLARE @PG_PromotionPrize INT = 50

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @PG_PromotionPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@PG_PromotionPrize, -1, 'Expense', -1, '', N' Deduct PG Soft Promotion')
END
