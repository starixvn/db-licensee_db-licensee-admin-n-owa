/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingDetailSel]
	@PayerId			INT
AS
/*  
	 Created: 20150420@Florent
	 Task : Get Payer setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:  
		- 20150618@Florent: add column Currency to LA_Minfee   		  
		- 20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
		- 20150831@Bravo: fix bug - Min fee term & Basis of billing max length.
		- 20150917@Victor: Support Chinese on Settings
		- 20161025@Scofield: exclude Colossus Bet from ChargeInfo
		- 20161031@bruce.bui: show CB and charge type
		- 20170216@bruce.bui: [#70050]
				+ sort product, include payername,
				+ sort charge rate by expired
		- 20180716@bruce: add new group TEST for credit [#98126] 
		- 20181115@Parsons: Configure discount settings by currency [#99694]
		- 20180731@Mason: Integrate-Card-Club [#116096]
		
	 Params:
		+ @PayerId :specify Party
		+ @@PayerGroup :	0 get all Party
							<> 0 specify Party
		+ @@DiscountGroup : 0 get all Party
							<> 0 specify Party
		+ @@RebateGroup :	0 get all Party
							<> 0 specify Party
	 Example:
				exec [LA_PayerSettingDetailSel] 15
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Rebate INT = 2
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @DiscountByGroupFee INT = 11
	DECLARE @DiscountByGroupGrosswin INT = 13

	DECLARE @ProductListAll		VARCHAR(500) = ''		
		, @MinDate				DATE 
		, @MaxDate				DATE
		, @CurrentDate			DATE

	SET @CurrentDate = CONVERT(DATE, GETDATE())
	DECLARE @ChargeInfo AS TABLE (ChargeId INT, PartyId INT, ProductId INT, BettypeRef INT, Rate MONEY, ChargeType SMALLINT, FromDate DATE, ToDate DATE, FirstBilling VARCHAR(100), BasisOfBilling NVARCHAR(MAX), ExchangeID INT)	
	DECLARE @Minfee AS TABLE(FeeId INT, PartyId INT, ProductId INT, FeeTypeId TINYINT, FeeAmount MONEY, CurrencyId INT, MinFeeTerm NVARCHAR(MAX), FromDate DATE, ToDate DATE)
	DECLARE @PayerSettingHeader AS TABLE(PartyId INT, PayerGroupID INT, PayerGroupName VARCHAR(100), ExchangeID INT, DiscountGroupID INT, DiscountGroupName VARCHAR(100), RebateGroupID INT, RebateGroupName VARCHAR(100))
	DECLARE @Discount AS TABLE(PartyId INT, ProductId INT, FromDate DATE, ToDate DATE,DiscountGroupId INT, DiscountGroupName VARCHAR(100), DiscountGroupType TINYINT)

	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '') -- dont support RB

	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PayerId
	
	INSERT INTO @ChargeInfo(ChargeId, PartyId, ProductId, BettypeRef, Rate, ChargeType, FromDate, ToDate, FirstBilling, BasisOfBilling, ExchangeID)
	SELECT c.ChargeID		
		, c.PartyID
		, c.ProductID		
		, CASE WHEN c.ProductID IN (14,17) THEN 
					c.Bettype
				 ELSE 0 END
		  AS BettypeRef
		, c.DI_Rate
		, ci.ChargeType
		, c.Fromdate
		, c.Todate
		, CASE WHEN c.ProductID IN (14,17) THEN cs.FirstOfBilling ELSE ci.FirstOfBilling END AS FirstOfBilling
		, CASE WHEN c.ProductID IN (14,17) THEN cs.BasisOfBilling ELSE ci.BasisOfBilling END AS BasisOfBilling
		, pd.BaseCurrencyId
	FROM dbo.LA_f_ChargeInfo(@PayerId, @MinDate, @MaxDate, @ProductListAll, 'OA', 1) c
		LEFT JOIN OAS_Party p WITH (NOLOCK) ON c.PartyID = p.PartyID
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID				
		LEFT JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON c.ChargeID = ci.ChargeID
		LEFT JOIN dbo.OAS_ChargeInfoSub cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeIdRef AND c.Bettype = cs.BettypeRef

	--======Min fee Area ===---
	INSERT INTO @Minfee(FeeId, PartyId, ProductId, FeeTypeId, FeeAmount, CurrencyId, MinFeeTerm, FromDate, ToDate)
	SELECT MinFeeId , PartyId, ProductId, FeeTypeId, FeeAmount, CurrencyId, MinFeeTerm, FromDate, ToDate 
	FROM dbo.LA_MinFee WITH (NOLOCK)
	WHERE PartyId = @PayerId

	--======Discount/ Rebate ===---
	INSERT INTO @Discount (PartyId, ProductId, FromDate, ToDate, DiscountGroupId, DiscountGroupName, DiscountGroupType)
	SELECT a.PartyID, p.ProductId, h.FromDate, h.ToDate, d.DiscountGroupId, h.DiscountGroupName, h.DiscountGroupType
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON a.DiscountGroupId = d.DiscountGroupId 
		INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId 
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
	WHERE a.PartyID = @PayerId
	GROUP BY a.PartyID, p.ProductId, h.FromDate, h.ToDate, d.DiscountGroupId, h.DiscountGroupName, h.DiscountGroupType

	-- product order
	DECLARE @ProductOrder TABLE(ProductId INT, ProductOrder SMALLMONEY)
	INSERT INTO @ProductOrder
	SELECT ProductId, CASE ProductId 
			WHEN 15/*CB*/ THEN 13.5 -- , make CB after BT and before MGCLC
			ELSE ProductId -- keep as it is
		END
	FROM dbo.LA_f_Products3rd('')

	-- payer setting
	SELECT TOP 1 c.PartyId			AS PayerID	
		, pg.PartyGroupId		AS PayerGroupId
		, pg.PartyGroupName		AS PayerGroupName
		, c.ExchangeID
		, d1.DiscountGroupId	AS DiscountGroupID
		, d1.DiscountGroupName	AS DiscountGroupName
		, d2.DiscountGroupId	AS RebateGroupID
		, d2.DiscountGroupName	AS RebateGroupName
		, CASE WHEN ISNULL(pd.BrandName,'')<>'' THEN pd.BrandName + ' (' +p.PartyName+')' ELSE p.PartyName END PayerName
	FROM @ChargeInfo c
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID=c.PartyId
		INNER JOIN dbo.OAS_PartyDetail pd ON pd.PartyId=c.PartyId
		LEFT JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK) ON  c.PartyId = pga.PartyId
		LEFT JOIN dbo.LA_PartyGroup pg WITH (NOLOCK) ON  pga.PartyGroupId = pg.PartyGroupId
		LEFT JOIN (
				SELECT PartyId, DiscountGroupId, DiscountGroupName 
				FROM @Discount 
				WHERE DiscountGroupType IN (@DiscountIndividualFee, @DiscountIndividualGrosswin, @DiscountByGroupFee, @DiscountByGroupGrosswin)
					AND @CurrentDate BETWEEN FromDate AND ToDate
				) d1 ON c.PartyId = d1.PartyId --discount
		LEFT JOIN (
				SELECT PartyId, DiscountGroupId, DiscountGroupName 
				FROM @Discount 
				WHERE DiscountGroupType = @Rebate
					AND @CurrentDate BETWEEN FromDate AND ToDate
				) d2 ON c.PartyId = d2.PartyId --Rebate

	-- charge rate setting
	;WITH Rate AS(
		SELECT c.ChargeId		AS ChargeId
			, c.PartyId			AS PayerID
			, c.ProductId		AS ProductId
			, ProductName		AS ProductName
			, FirstBilling		AS FirstBilling
			, REPLACE(c.BasisOfBilling,'&amp;','&') BasisOfBilling
			, c.BettypeRef
			, c.Rate			AS Rate
			, c.ChargeType
			, c.FromDate
			, c.ToDate
			, CASE WHEN @CurrentDate > c.ToDate THEN 1 ELSE 0 END IsExpired
			, po.ProductOrder
		FROM @ChargeInfo c
		INNER JOIN dbo.LA_f_Products3rd('') pr ON c.ProductID = pr.ProductID
		INNER JOIN @ProductOrder po ON c.ProductID = po.ProductId
	)
	SELECT *
	FROM Rate
	ORDER BY IsExpired, ProductOrder, FromDate

	--Minfee Setting
	SELECT  m.FeeId			AS MinFeeId
		, PartyId			AS PayerID
		, m.ProductId		AS ProductId
		, pr.ProductName	AS ProductName
		, FeeAmount
		, CurrencyId
		, e.Code			AS CurrencyName
		, REPLACE(MinFeeTerm,'&amp;','&') MinFeeTerm
		, FromDate
		, ToDate
	FROM @Minfee m
		INNER JOIN dbo.LA_f_Products3rd('') pr ON m.ProductID = pr.ProductID
		INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON m.CurrencyId = e.exchangeid
		INNER JOIN @ProductOrder po ON pr.ProductID = po.ProductId
	WHERE FeeTypeId = 1 -- Miniumfee
	ORDER BY po.ProductOrder, m.FromDate
	 
	--Waive Setting
	SELECT w.FeeId			AS WaiveId
		, PartyId			AS PayerID
		, w.ProductId		AS ProductId
		, pr.ProductName	AS ProductName
		, FromDate
		, ToDate
	FROM @Minfee w
		INNER JOIN dbo.LA_f_Products3rd('') pr ON w.ProductID = pr.ProductID
		INNER JOIN @ProductOrder po ON pr.ProductID = po.ProductId
	WHERE w.FeeTypeId = 2 -- waive
	ORDER BY po.ProductOrder, w.FromDate
END
GO