/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_PartyHasBillingSel]
	@DiscountGroupId INT
AS
/*  
	 Created: 20180702@Parsons [#94282]
	 Task: Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180702@Parsons: Select party list has billing [#94282]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]

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

	SELECT DISTINCT ih.PartyId
	FROM LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @PartieSettings p ON ih.PartyId = p.PartyId AND id.ProductId = p.ProductId	
	WHERE ih.ToDate >= @FromDateDiscount AND ih.ToDate <= @ToDateDiscount
			AND ih.InvoiceType = @InvoiceTypeDiscount 
			AND ih.StatusId <> -1 -- void
END
GO