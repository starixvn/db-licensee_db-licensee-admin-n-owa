/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_HasBilling]
	@DiscountGroupId INT, 
	@HasBilling BIT = 0 OUTPUT
AS
/*  
	 Created: 20180702@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180702@Parsons: Check this discount has not belong to any a invoice yet [#94282]

	 Params:

	 Explannation: 
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @FromDateDiscount DATETIME, @ToDateDiscount DATETIME, @InvoiceTypeDiscount INT = 1
	DECLARE @PartieSettings TABLE(PartyId INT, ProductId INT)
	DECLARE @ProductsSettings TABLE(PartyId INT, ProductId INT)

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

	--#Region Check has not belong to any a invoice yet
	IF(EXISTS(SELECT TOP 1 ih.PartyId
		FROM LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @PartieSettings p ON ih.PartyId = p.PartyId AND id.ProductId = p.ProductId
		WHERE ih.FromDate >= @FromDateDiscount AND ih.ToDate <= @ToDateDiscount
			  AND ih.InvoiceType = @InvoiceTypeDiscount 
			  AND ih.StatusId = 0 -- normal invoice
	))
	BEGIN
		SELECT @HasBilling = 1
	END
	ELSE
	BEGIN
		SELECT @HasBilling = 0
	END
	--#Endregion Check has not belong to any a invoice yet
END
GO