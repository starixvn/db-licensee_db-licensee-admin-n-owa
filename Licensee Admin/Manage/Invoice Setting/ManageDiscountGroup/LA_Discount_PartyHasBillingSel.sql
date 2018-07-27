/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_PartyHasBillingSel]
	@DiscountGroupId INT
AS
/*  
	 Created: 20180702@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180702@Parsons: Select party list has billing [#94282]

	 Params:

	 Explannation: EXEC LA_Discount_PartiesBillingSel @DiscountGroupId = 277
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @FromDateDiscount DATETIME, @ToDateDiscount DATETIME, @InvoiceTypeDiscount INT = 1
	DECLARE @PartieSettings TABLE(PartyId INT, ProductId INT)

	--#Region Get info of Discount 
	-- Get Time range
	SELECT @FromDateDiscount = FromDate, @ToDateDiscount = ToDate
	FROM LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	-- Get Party List
	INSERT INTO @PartieSettings(PartyId, ProductId)
	SELECT a.PartyID, p.ProductId
	FROM LA_DiscountGroupHeader h WITH(NOLOCK) 	 
		INNER JOIN LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		INNER JOIN LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId = p.DiscountGroupId
	WHERE h.DiscountGroupId = @DiscountGroupId 
	--#Endregion Get info of Discount

	SELECT ih.PartyId
	FROM LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @PartieSettings p ON ih.PartyId = p.PartyId AND id.ProductId = p.ProductId
	WHERE ih.FromDate >= @FromDateDiscount AND ih.ToDate <= @ToDateDiscount
			AND ih.InvoiceType = @InvoiceTypeDiscount 
			AND ih.StatusId = 0 -- normal invoice
END
GO