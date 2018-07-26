/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_AreLicenseesHasBillingYet]
	@DiscountGroupId			INT, 
	@PartyIds					VARCHAR(512)	= '', 
	@HasBilling					BIT				= 1	OUTPUT
AS
/*  
	 Created: 20180726@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180726@Parsons: check parties have not belong to any a invoice yet  [#94282]
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FromDateDiscount DATETIME, @ToDateDiscount DATETIME, @InvoiceTypeDiscount INT = 1
	DECLARE @PartySettings TABLE(PartyId INT)
	DECLARE @ProductSettings TABLE(ProductId INT)

	INSERT INTO @PartySettings (PartyId)
	SELECT val FROM bodb02.dbo.strSplit(@PartyIds, ',')

	INSERT INTO @ProductSettings (ProductId)
	SELECT ProductId FROM LA_DiscountGroupProduct WHERE DiscountGroupId = @DiscountGroupId

	-- Get Time range
	SELECT @FromDateDiscount = FromDate, @ToDateDiscount = ToDate
	FROM LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--#Region Check has not belong to any a invoice yet
	IF ((EXISTS(SELECT TOP 1 ih.PartyId
		FROM LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @PartySettings p ON ih.PartyId = p.PartyId
		INNER JOIN @ProductSettings pd ON id.ProductId = pd.ProductId
		WHERE ih.FromDate >= @FromDateDiscount AND ih.ToDate <= @ToDateDiscount
			  AND ih.InvoiceType = @InvoiceTypeDiscount 
			  AND ih.StatusId = 0 -- normal invoice
	)))
	BEGIN
		SET @HasBilling = 1
	END
	ELSE
	BEGIN
		SET @HasBilling = 0
	END
END
GO
