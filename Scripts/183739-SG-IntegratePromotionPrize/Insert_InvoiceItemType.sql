/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20230217@Danny
	DB: DBCUST.bodb_Licensee
	Task: SG - Promotion prize integration [#183739]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Deduct SG Promotion
*/
USE bodb_Licensee
GO

DECLARE @SG_PromotionPrize INT = 49

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @SG_PromotionPrize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@SG_PromotionPrize, -1, 'Expense', -1, '', N'Deduct SG Promotion')
END