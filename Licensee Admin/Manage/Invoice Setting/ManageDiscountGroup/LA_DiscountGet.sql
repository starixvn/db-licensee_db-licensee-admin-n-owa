/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountGet]
	@GroupId INT
AS
/*  
	 Created: 20180628@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180628@Parsons: Get discount groups info [#94282]
		- 20181022@Parsons: Configure discount settings by currency [#99694]
		- 20200225@Parsons: Support-HID-currency [#128856]
		- 20200609@Mason: Special handling for INH market [#128570]

	 Params:

	 Explannation: EXEC LA_DiscountGet @GroupId = 0
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ToBeCalculated TINYINT = 1
	DECLARE @ToBeDiscounted TINYINT = 0
	DECLARE @CalculateAndDiscount TINYINT = 10

	--get products which has assigned to group
	DECLARE 
		@CalculationProductIds VARCHAR(1000), 
		@DiscountProductIds VARCHAR(1000),
		@CalculationProductList VARCHAR(4000), 
		@DiscountProductList VARCHAR(4000)

	SELECT @CalculationProductIds = COALESCE(@CalculationProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR))
		 ,@CalculationProductList = COALESCE(@CalculationProductList + ',' + p.ProductName, p.ProductName)
	FROM dbo.LA_DiscountGroupProduct_UAT d WITH(NOLOCK)
	INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
	WHERE d.DiscountGroupId = @GroupId AND d.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)

	SELECT @DiscountProductIds = COALESCE(@DiscountProductIds + ',' + CAST(p.ProductId AS VARCHAR), CAST(p.ProductId AS VARCHAR))
		 ,@DiscountProductList = COALESCE(@DiscountProductList + ',' + p.ProductName, p.ProductName)
	FROM dbo.LA_DiscountGroupProduct_UAT d WITH(NOLOCK)
	INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
	WHERE d.DiscountGroupId = @GroupId AND d.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount)

	--get discount header
	SELECT h.DiscountGroupId
		, h.DiscountGroupType
		, h.DiscountGroupName
		, c.exchangeid				AS CurrencyId
		, c.Code					AS CurrencyName
		, h.FromDate
		, h.ToDate
		, @CalculationProductIds	AS CalculationProductIds
		, @DiscountProductIds		AS DiscountProductIds
		, @CalculationProductList	AS CalculationProductList
		, @DiscountProductList		AS DiscountProductList
		, h.ModifiedDate
	FROM dbo.LA_DiscountGroupHeader_UAT h WITH(NOLOCK)
		INNER JOIN bodb02.dbo.exchange c WITH (NOLOCK) ON c.exchangeid = h.CurrencyId
	WHERE DiscountGroupId = @GroupId
	-- endregion

	--get discount setting rates
	SELECT DiscountGroupDetailId AS DiscountDetailId
		, FromAmount
		, ToAmount
		, Rate
	FROM dbo.LA_DiscountGroupDetail_UAT WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
	ORDER BY FromAmount
	-- endregion

	--get list of licensees
	DECLARE @PartyTable AS TABLE(DiscountGroupId SMALLINT, PartyId INT, PartyName VARCHAR(50), IsApplyDiscount BIT, Remark NVARCHAR(4000), IsSpecialTreatment BIT)
	
	INSERT INTO @PartyTable(DiscountGroupId, PartyId , PartyName, IsApplyDiscount, Remark, IsSpecialTreatment)
	SELECT DiscountGroupId,
			p.PartyId,
			p.PartyName,
			IsApplyDiscount,
			Remark,
			a.IsSpecialTreatment
	FROM dbo.LA_DiscountGroupAssignment_UAT a WITH(NOLOCK)
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = a.PartyID
	WHERE DiscountGroupId = @GroupId

	SELECT DiscountGroupId,PartyId,PartyName,IsApplyDiscount,Remark,IsSpecialTreatment
	FROM @PartyTable
	--endregion 

	--get list of currency
	DECLARE @CurrenciesOfLicensee TABLE (PartyId INT, CurrencyId INT, CurrencyCode VARCHAR(20), CurrencyName VARCHAR(20))
	
	INSERT INTO @CurrenciesOfLicensee(PartyId, CurrencyId, CurrencyCode, CurrencyName)
	SELECT DISTINCT p.PartyId, lc.Currency, 
					CASE WHEN lc.Currency = 92 THEN 'HID' ELSE e.Code END AS Code, 
					CASE WHEN lc.Currency = 51 THEN 'VND' ELSE e.currency END AS CurrencyName
	FROM dbo.f_SelLicenseeCust(0) AS lc
	INNER JOIN dbo.OAS_Party pp WITH (NOLOCK) ON lc.LicenseeID = pp.OldRefID 
	INNER JOIN @PartyTable p ON pp.PartyID = p.PartyId
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
	WHERE lc.Currency <> 20 -- exclude test

	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM @CurrenciesOfLicensee c1
	INNER JOIN (
		SELECT PartyId, CurrencyCode
	    FROM @CurrenciesOfLicensee
	    GROUP BY PartyId, CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.PartyId = c2.PartyId AND c1.CurrencyCode = c2.CurrencyCode

	SELECT c.PartyId, c.CurrencyId, c.CurrencyCode AS CurrencyName, CASE WHEN d.CurrencyId IS NOT NULL THEN 1 ELSE 0 END IsSelected
	FROM @CurrenciesOfLicensee c
	LEFT JOIN LA_DiscountGroupCurrency_UAT d WITH(NOLOCK) ON
		d.PartyID = c.PartyId AND 
		d.DiscountGroupId = @GroupId AND
		(d.CurrencyId = 0 OR d.CurrencyId = c.CurrencyId) -- all currency = 0
END
GO