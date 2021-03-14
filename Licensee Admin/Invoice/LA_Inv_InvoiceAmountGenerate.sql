/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceAmountGenerate]
	@PartyId			INT,
	@BillerId			INT,
	@InvoiceTypeId		INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@ProductCodes		VARCHAR(500),
	@Environment		VARCHAR(50),
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT,
	@BaseCurrency		VARCHAR(10)		= 'EUR'	OUTPUT,
	@InvoiceTemplateName VARCHAR(200)	= ''	OUTPUT,
	@HostingFeesExchangeName VARCHAR(20)= ''	OUTPUT,
	@HostingFeesExchangeRate FLOAT		= 0		OUTPUT,
	@HostingFeesAmount MONEY			= 0		OUTPUT,
	@HostingFeesMaxPCU INT				= 0		OUTPUT,
	@IsWaived BIT						= 0		OUTPUT
WITH RECOMPILE
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20150806@Bravo.Tran: Invoice Amount - Generate
		- 20150922@Bravo.Tran: Invoice Amount - Fix bug wrong Total amount under Discount.
		- 20151109@Bravo.Tran: Invoice Amount - Enhance prorate min fee.
		- 20160627@Bravo.Tran: Invoice Amount - Hosting Fess amount.
		- 20160719@Bruce.Bui: Adding hosting fees extra info.
		- 20160927@Bruce.Bui: Get MaxPCU case full month waive
		- 20161024@Bruce.Bui: Add new discount type = 3
		- 20160927@Bruce.Bui: Get MaxPCU case full month waive
		- 20161104@Scofield.Huynh: Update for CB
		- 20170306@bruce: include BA amount =0 [RedmindID: #72806]
		- 20170307@Scofield: include amount = 0 for all products [RedmindID: #72806]
		- 20170403@Scofield: update for Cashout [RedmindID: #73310]
		- 20170404@Harper: using new sum table for Cashout Product [RedmindID: #73310]
		- 20170505@Bruce: Correct Product name in Description [RedmindID: #75950]
		- 20170718@Bruce: restructure invoice db [RedmindID: #79905]
		- 20170721@Scofield: Update Amount Type [#79905]
		- 20170721@Bruce: Calculate AMF amount [#76410]
		- 20171002@Bruce: add environment to parameter list [#84038]
		- 20171027@Bruce: show individual discount by product [#85256]		
		- 20171113@Bruce: Modified error message [RedmineID: #84163]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180110@Bruce: deduct against invoice [#87039]
		- 20180419@Scofield: update CB for FreePlay [#93907]
		- 20180525@Scofield: Incorporate 9wickets' data [#94950]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180712@Bruce: Enhance Manage Discount group [#94282]
		- 20181002@Parsons: Integrate AG setup fee into invoices [#98485]
		- 20200228@Parsons: Support-HID-currency [#128856]
		- 20200406@Parsons: Issue rebate worksheet [#131874]
		- 20201202@Parsons: Add more condition to get only one rebate setting at the one time [#142345]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]

	USE bodb_Licensee
	DECLARE @FromDate DATETIME = '2016-06-01'
	DECLARE @ToDate DATETIME  = '2016-06-30'
	--DECLARE @FromDate DATETIME = '2012-11-01'
	--DECLARE @ToDate DATETIME  = '2012-11-30'
	--DECLARE @FromDate DATETIME = '2013-11-01'
	--DECLARE @ToDate DATETIME  = '2013-11-30'
	DECLARE @PartyId INT = 14
	DECLARE @BillerId INT = 150
	DECLARE @InvoiceTypeId INT = 8
	DECLARE @ProductCodes VARCHAR(100)='SB,BA,RB,NG,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG,BT,MGC'
	DECLARE	@ErrCode INT
	DECLARE	@ErrMsg NVARCHAR(1000)
	DECLARE	@BaseCurrency NVARCHAR(20)
	DECLARE @InvoiceTemplateId VARCHAR(200)
	
	EXEC [LA_Inv_InvoiceAmountGenerate] @PartyId,@BillerId,@InvoiceTypeId, @FromDate, @ToDate, @ProductCodes, @ErrCode OUT, @ErrMsg OUT, @BaseCurrency OUT, @InvoiceTemplateId OUT
	SELECT @ErrCode, @ErrMsg, @BaseCurrency, @InvoiceTemplateId
*/
BEGIN
	SET NOCOUNT ON
	-- Region: Check Invoice Type is Rebate
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @EmptyTable AS TABLE(
			ProductId	INT,
			ProductCode	VARCHAR(20),
			Productname	VARCHAR(200),
			InvoiceAmount MONEY,
			WithoutWaivedAmount MONEY,
			AmountType	TINYINT
	)

	-- Region: Get base Currency
	DECLARE @BaseCurrencyId INT = 12
	DECLARE @BaseCurrencyName VARCHAR(10) = 'GBP'

	SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId
	FROM OAS_PartyBaseCurrency WITH(NOLOCK)
	WHERE PartyID = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate
	
	IF(@BaseCurrencyId IS NULL)
	BEGIN
		SET @BaseCurrencyId = 12 -- default GBP
	END
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(Id,Name)
	EXECUTE dbo.LA_SelBaseCurrency
	
	SELECT	@BaseCurrencyName = Name
	FROM	@BaseCurrencyTable bct
	WHERE	@BaseCurrencyId = bct.Id
	
	SELECT @BaseCurrency = @BaseCurrencyName	
	-- End Region	

	-- Region: Get template
	SELECT @InvoiceTemplateName = ( SELECT	TOP 1 t.InvTemplateName
									FROM	dbo.LA_InvoiceSetting i WITH(NOLOCK)
											INNER JOIN dbo.LA_InvoiceTemplate t WITH(NOLOCK) ON i.InvTempId = t.InvTemplateId
									WHERE	i.FromPartyId = @PartyId
											AND i.ToPartyId = @BillerId
											AND i.InvTypeId = @InvoiceTypeId)
	-- End Region

	-- Region: Get exchange rate info
	CREATE TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- End region
	
	DECLARE @InvoiceTypeHostingFeesId INT = 6,
		@AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@AmountTypeRackHostingFee INT = 8,
		@AmountTypeMonthlyHostingFee INT = 9,
		@DeductAgainstInvoice INT = 24

	IF @InvoiceTypeId = @InvoiceTypeHostingFeesId
	BEGIN
		-- Get charge rate settings
		DECLARE @Settings TABLE(
			ChargeId	INT,
			SettingType TINYINT,
			FromParty	INT, 
			FromDate	DATETIME, 
			ToDate		DATETIME,
			InputFromDate DATETIME,
			InputToDate DATETIME,
			DaysInMonth FLOAT,
			NumOfApplyDate	FLOAT,
			ProductName VARCHAR(50),
			FeesId		INT,
			FeesType	TINYINT,
			BaseProduct INT,
			IsSameExchange BIT
		)

		INSERT INTO @Settings(ChargeId, SettingType, FromParty, FromDate, ToDate, InputFromDate, InputToDate, DaysInMonth, ProductName, FeesId, FeesType, BaseProduct, IsSameExchange)
		SELECT s.ChargeId, s.SettingType, s.FromParty, s.FromDate, s.ToDate, @FromDate, @ToDate, @DaysInMonth, s.ProductName, f.HostingFeesId, f.HostingFeesTypeId, s.BasedMinimunFees,
			CASE WHEN s.BaseCurrencyId = f.BaseCurrencyId AND s.BaseCurrencyId = @BaseCurrencyId THEN 1 ELSE 0 END
		FROM dbo.LA_HostingFeesSetting s WITH(NOLOCK)
			LEFT JOIN dbo.LA_HostingFees f WITH(NOLOCK) ON s.HostingFeesId = f.HostingFeesId
		WHERE s.FromParty = @PartyId
			AND (@FromDate BETWEEN s.FromDate AND s.ToDate OR @ToDate BETWEEN s.FromDate AND s.ToDate)

		SET @ErrCode = 0
		IF EXISTS (SELECT TOP 1 * FROM @Settings WHERE IsSameExchange = 0 AND SettingType = 1 ORDER BY FromDate DESC)
		BEGIN
			SET @ErrCode = 80
			SET @ErrMsg = 'Please check the Exchange settings of Hosting Charge Rate. Exchange of the setting must be the same with Payer'' exchange'
		END
		ELSE
		BEGIN
			UPDATE @Settings
			SET NumOfApplyDate = CONVERT(MONEY, CASE WHEN InputToDate < ToDate THEN InputToDate ELSE ToDate END - CASE WHEN InputFromDate > FromDate THEN InputFromDate ELSE FromDate END) + 1

			-- if there is multiple setting, use the latest
			DECLARE @NumOfApplyDate INT = ISNULL((SELECT SUM(NumOfApplyDate) FROM @Settings WHERE SettingType = 1), 0)
			DELETE @Settings WHERE SettingType = 1 AND FromDate < (SELECT MAX(s.FromDate) FROM @Settings s WHERE s.SettingType=1)

			-- check waived status
			DECLARE @NumOfWaivedDays INT = ISNULL((SELECT SUM(NumOfApplyDate) FROM @Settings WHERE SettingType = 2), 0)
			SET @IsWaived = (CASE WHEN @NumOfWaivedDays > 0 THEN 1 ELSE 0 END)

			UPDATE @Settings
			SET NumOfApplyDate = @NumOfApplyDate - @NumOfWaivedDays
			WHERE SettingType = 1

			IF (SELECT COUNT(*) FROM @Settings WHERE SettingType = 1) = 0
			BEGIN 
				SET @ErrCode = 81
				SET @ErrMsg = 'There is no hosting fees charge rate settings!'
			END
			ELSE
			BEGIN
				DECLARE @FeesType TINYINT = (SELECT FeesType FROM @Settings WHERE SettingType = 1)
				IF @FeesType = 1 -- Fixed
				BEGIN
					INSERT INTO @EmptyTable
					SELECT p.Productid, p.ProductPrefix, s.ProductName, s.NumOfApplyDate/s.DaysInMonth * d.Amount * e.Rate, d.Amount * e.Rate, @AmountTypeRackHostingFee
					FROM @Settings s INNER JOIN dbo.Product3rd p WITH(NOLOCK) ON s.ProductName = p.ProductName
						INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId
						INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
					WHERE s.SettingType = 1
				END
				ELSE -- VCM
				BEGIN 
					DECLARE @CurrentUser TABLE (TotalUser INT, LogDate DATETIME)
					INSERT INTO @CurrentUser
					EXEC LA_PeakConcurrentUsersSel @PartyId, @FromDate, @ToDate

					-- If waive is applied then get max pcu out of waive range
					SET @HostingFeesMaxPCU = ISNULL((SELECT MAX(c.TotalUser) FROM @CurrentUser c WHERE c.TotalUser NOT IN (
						SELECT TotalUser FROM @CurrentUser c2 INNER JOIN @Settings s ON c2.LogDate BETWEEN s.FromDate AND s.ToDate WHERE s.SettingType = 2
					)),0)

					-- if maxpcu = 0 it means this is full range waive then get maxpcu for reference
					IF @HostingFeesMaxPCU = 0 SET @HostingFeesMaxPCU = (SELECT MAX(TotalUser) FROM @CurrentUser)
					
					INSERT INTO @EmptyTable
					SELECT p.Productid, p.ProductPrefix, s.ProductName, s.NumOfApplyDate/s.DaysInMonth * d.Amount * e.Rate, d.Amount * e.Rate, @AmountTypeMonthlyHostingFee
					FROM @Settings s INNER JOIN dbo.Product3rd p WITH(NOLOCK) ON s.ProductName = p.ProductName
						INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId AND @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
						INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
					WHERE s.SettingType = 1
				END

				SELECT TOP 1	@HostingFeesAmount = d.Amount,
								@HostingFeesExchangeName = CASE e.ExchangeID
																WHEN 75 THEN 'PTU'
																WHEN 76 THEN 'PS'
																WHEN 77 THEN 'PTH'
																WHEN 92 THEN 'HID'
																ELSE e.CurrencyCode
															END,
								@HostingFeesExchangeRate = e.Rate
				FROM @Settings s
					INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId
					INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
				WHERE s.SettingType = 1 AND (
					d.VCMFrom IS NULL OR @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
				)
			END
		END
		
		DECLARE @BaseProduct INT = (SELECT BaseProduct FROM @Settings WHERE SettingType = 2)
		SET @ProductCodes = CASE 
			WHEN @BaseProduct = 0 THEN 'SB'
			ELSE (SELECT ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @BaseProduct)
		END
		
		IF (@ErrCode != 0 OR @BaseProduct IS NULL)
		BEGIN
			SELECT * FROM @EmptyTable
			DROP TABLE #Exchange
			RETURN
		END
	END
		
	IF @InvoiceTypeId = 3 -- rebate
	BEGIN
		DECLARE @ProductCodeString VARCHAR(500) = ''
		SELECT  @ProductCodeString = @ProductCodeString + p.ProductCode + ','
		FROM(
				SELECT	CASE 
							WHEN dp.ProductId = 0 THEN 'SB'
							ELSE p.ProductPrefix 
						END AS ProductCode
				FROM	dbo.LA_DiscountGroupProduct dp WITH(NOLOCK)
						LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON dp.ProductId = p.Productid
						INNER JOIN dbo.LA_DiscountGroupHeader dh WITH(NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
						INNER JOIN dbo.LA_DiscountGroupAssignment da WITH(NOLOCK) ON dh.DiscountGroupId = da.DiscountGroupId
				WHERE	da.PartyID = @PartyId
						AND dh.DiscountGroupType = 2 -- Rebate
						AND dh.FromDate <= @ToDate
						AND dh.ToDate >= @FromDate
			) p
				
		IF @ProductCodeString = '' OR @ProductCodeString = ','
		BEGIN
			SELECT @ErrCode = 1, @ErrMsg = 'There is no setting for Rebate in the Rebate Group. Please set it before proceeding further.'
			SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
			RETURN
		END
		ELSE
		BEGIN
			SET @ProductCodes = SUBSTRING(@ProductCodeString, 1, LEN(@ProductCodeString) - 1)
		END
	END
	-- EndRegion
	
	-- get amount to company,discount,rebate(only for some supported products
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Winloss			MONEY,
		Fee				MONEY,
		Discount		MONEY,
		DiscountRate	MONEY,
		DiscountRemark	NVARCHAR(4000),
		Rebate			MONEY,
		RebateRate		MONEY,
		RebateRemark	NVARCHAR(4000),
		NegativeFee		MONEY,
		Minfee			MONEY,
		IsChargedByMinFee BIT
	)
	INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
	EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@PartyId,@ProductCodes,@BaseCurrencyName

	-- Region: Get party charge rate info	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef  INT,
			Rate		MONEY,
			TypeId		SMALLINT,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId NOT IN (1, 15) --exclude RB, CB
	)

	-- exclude products have calculated
	DELETE @PartyChargeInfo WHERE ProductID IN (SELECT a.ProductId FROM #AmountToCompany a)
	
	-- Get ChargeInfo for CB
	DECLARE @CommChargeType INT = 6
	DECLARE @CashInShareChargeType INT = 7
	DECLARE @CBProductId INT = 15
	DECLARE @COProductId INT = 25

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
	SELECT	ci.FromParty,
			CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END AS LicenseeId,
			@CBProductId,
			ci.Rate,
			ci.ChargeType,
			CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
			CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
		LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
		LEFT JOIN dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE EXISTS(SELECT val FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'CB')
		AND FromParty = @PartyId
		AND ProductID = @CBProductId
		AND ChargeType IN (@CommChargeType,@CashInShareChargeType)
		AND @FromDate <= ci.ToDate
		AND ci.FromDate <= @ToDate
	-- End Get ChargeInfo for CB

	-- check payer exchange & minfee exchange
	--
	DECLARE @PartyGroups TABLE(PartyId INT, CurrencyId INT)
	INSERT INTO @PartyGroups(PartyId, CurrencyId)
	(
		SELECT d.PartyId, d.BaseCurrencyId
		FROM dbo.LA_PartyGroup g WITH(NOLOCK)
		INNER JOIN dbo.LA_PartyGroupAssignment a WITH(NOLOCK) ON a.PartyGroupId=g.PartyGroupId
		INNER JOIN dbo.LA_PartyGroupAssignment b WITH(NOLOCK) ON a.PartyGroupId=b.PartyGroupId
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=b.PartyId
		WHERE a.PartyId = @PartyId
	)
	IF NOT EXISTS (SELECT TOP 1 1 FROM @PartyGroups)
	BEGIN
		INSERT INTO @PartyGroups(PartyId, CurrencyId) VALUES (@PartyId, @BaseCurrencyId)
	END

	IF EXISTS (
		SELECT TOP 1 m.PartyId
		FROM @PartyGroups p
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON m.PartyId=p.PartyID AND m.FeeTypeId = 1 -- 1 = minfee
		WHERE m.FromDate <=@ToDate AND m.ToDate >= @FromDate AND p.CurrencyId <> m.CurrencyId
	)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Please check the Exchange settings of Payer''s minfee or minfee group. Exchange of minfee or minfees in group should be the same with Payer''s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END

	-- check payer exchange & discount exchange
	--
	DECLARE @DiscountCurrency INT = (
		SELECT TOP 1 h.CurrencyId
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId=h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId=p.DiscountGroupId
		INNER JOIN #AmountToCompany c ON c.PartyId = a.PartyID AND c.ProductId=p.ProductId
		WHERE h.DiscountGroupType != 2 -- rebate
			AND h.FromDate <= @ToDate
			AND h.ToDate >= @FromDate
			AND a.PartyID = @PartyId
			AND a.IsApplyDiscount = 1
			AND ISNULL(c.DiscountRate,0) > 0
			AND p.CalculationType IN (0,10) -- 0: discount, 10: discount & calculate
		ORDER BY h.ToDate DESC
	)

	IF @DiscountCurrency IS NOT NULL AND @DiscountCurrency != @BaseCurrencyId
	BEGIN
		SELECT @ErrCode = 2, @ErrMsg = 'Please check the Exchange settings of Payer''s discount. Exchange of discount must be the same with Payer''s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			LicenseeId		INT, 
			PartyId			INT, 
			rptDate			DATETIME, 
			CurrencyId		INT, 
			WinLoss			MONEY, 
			AComm			MONEY, 
			ProductId		TINYINT,
			BettypeRef		INT, 
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,BettypeRef)
	(
		SELECT	b.SiteID,
				p.PartyId, 
				b.rptDate, 
				b.CurrencyID, 
				SUM(ISNULL(b.MemberWL, 0)) Winloss, 
				SUM(ISNULL(b.CommissionA, 0)) AS AComm, 
				p.ProductId,
				r.BettypeRef
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				LEFT JOIN dbo.Sport_Bettype_Reference r WITH (NOLOCK) ON b.Bettype = r.Bettype
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.Bettype = -1 OR r.BettypeRef = p.BettypeRef)
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate			
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.ProductId NOT IN (@CBProductId, @COProductId)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, r.BettypeRef
	)
	
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

	UPDATE	#TempData
	SET		AmountToCompany =	CASE  
									WHEN td.ProductId = 3 THEN (-td.WinLoss * p.Rate - td.AComm) * e.Rate
									WHEN td.ProductId <> 3 THEN (-td.WinLoss * p.Rate) * e.Rate
									ELSE 0 
								END
	FROM	#TempData td 
			INNER JOIN @PartyChargeInfo p 
				ON td.LicenseeId = p.LicenseeId 
				AND ((td.ProductId = p.ProductID AND td.ProductId NOT IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK)))
						OR 
					(td.ProductId = p.ProductID AND td.BettypeRef = p.BettypeRef AND td.ProductId IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK))))
				AND td.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID
	-- End region	
	
	-- Region: Get Amount By Product CB
	CREATE TABLE #TempDataCB (
		rptDate				DATETIME,
		LicenseeId			INT,
		PartyId				INT,
		ProductId			INT,
		CurrencyId			INT,
		Turnover			MONEY,
		TurnoverForCommision MONEY,
		TurnoverExchanged	MONEY,
		WinningPrize		MONEY,
		CashOut				MONEY,
		CommisionShare		MONEY,
		CashInShare			MONEY,
		CashInAmount		MONEY
	)
		
	INSERT INTO #TempDataCB (rptDate, LicenseeId, PartyId, ProductId, CurrencyId, Turnover, TurnoverForCommision, WinningPrize, CashOut, CashInAmount)
	SELECT	rptDate,
			b.SiteID,
			cb.PartyId,
			b.ProductId,
			CurrencyId,
			SUM(Turnover) Turnover,
			SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
			SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
			SUM(ISNULL(CashOutAmount,0)) CashOut,
			SUM(ISNULL(BuyBackAmount,0)) CashInAmount
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	JOIN @PartyChargeInfo cb ON b.SiteID = cb.LicenseeId AND b.ProductId = cb.ProductID AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
	WHERE	b.ProductId = @CBProductId AND 
		b.StatusId NOT IN (-1, 101, 102, 103) AND
		CustomerCategory NOT IN (27, 28) AND 
		CurrencyId <> 20 AND 
		cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
	GROUP BY rptdate, CurrencyId, b.SiteID, cb.PartyId, b.ProductId
	
	UPDATE #TempDataCB
	SET CommisionShare = td.TurnoverForCommision * cm.Rate, CashInShare = td.CashInAmount * ci.Rate
	FROM #TempDataCB td
	JOIN @PartyChargeInfo AS cm ON cm.ProductID = @CBProductId AND cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
	JOIN @PartyChargeInfo AS ci ON cm.ProductID = @CBProductId AND ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	SELECT LicenseeId, PartyId, rptDate, CurrencyId, ProductId, (Turnover - WinningPrize - Cashout - CommisionShare - CashInShare) * e.Rate
	FROM #TempDataCB tcb
	INNER JOIN #Exchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID	
	-- End region: Get Amount By Product CB
	
	-- Region: Get Amount By Product CO
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	(
		SELECT
			d.LicenseeId,			
			d.PartyId,
			d.Winlostdate,
			d.Currency,
			@COProductId,
			(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate AS AmountToCompany
		FROM (
			SELECT p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency,
				SUM(b.BuyBackAmt) AS BuyBackAmountSB,
				SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
				SUM(b.TicketPayout) AS TicketsPayout,					
				SUM(b.BuyBackAmt  * p.Rate) AS CashoutCommission	
			FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.ProductId = p.ProductID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
			WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate									
				AND b.ProductID = 25	
				AND b.Currency <> 20
				AND b.RoleID = 1 -- Member Level			
			GROUP BY p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency
		) d
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.Currency = e.ExchangeID	
	)
	-- End region: Get Amount By Product CO

	DECLARE @InvoiceData	TABLE(
			PartyId			INT,
			ProductId		INT, 
			InvoiceAmount	MONEY, 
			AmountType		TINYINT,
			Rate			MONEY,
			Remark			NVARCHAR(4000))
		
	IF @InvoiceTypeId = @InvoiceTypeHostingFeesId
	BEGIN 
		DECLARE @IsApplyMinFee BIT = ISNULL((SELECT TOP 1 1 FROM #AmountToCompany WHERE PartyId = @PartyId AND IsChargedByMinFee=1),0)

		-- Apply Min fee => Not waived
		-- No Min fee => waived
		SET @IsWaived = (CASE WHEN @IsApplyMinFee = 1 THEN 0 ELSE 1 END)

		IF @IsWaived = 0 AND @FeesType = 2 -- VCM and not waive then re-calculate max PCU
		BEGIN
			SET @HostingFeesMaxPCU =ISNULL((SELECT MAX(TotalUser) FROM @CurrentUser),0)
			
			DELETE @EmptyTable

			INSERT INTO @EmptyTable
			SELECT p.Productid, p.ProductPrefix, s.ProductName, 0, d.Amount * e.Rate, @AmountTypeMonthlyHostingFee
			FROM @Settings s INNER JOIN dbo.Product3rd p WITH (NOLOCK) ON s.ProductName = p.ProductName
				INNER JOIN dbo.LA_HostingFeesDetail d WITH (NOLOCK) ON s.FeesId = d.HostingFeesId AND @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
				INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
			WHERE s.SettingType = 1

			SELECT TOP 1	@HostingFeesAmount = d.Amount,
							@HostingFeesExchangeName = e.CurrencyCode,
							@HostingFeesExchangeRate = e.Rate
			FROM @Settings s
				INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON s.FeesId = d.HostingFeesId
				INNER JOIN #Exchange e ON d.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = @ToDate
			WHERE s.SettingType = 1 AND (@HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo)
		END

		SELECT ProductId,
			ProductCode,
			Productname,
			CASE WHEN @IsWaived = 1
				THEN InvoiceAmount
				ELSE WithoutWaivedAmount
			END AS InvoiceAmount,
			AmountType
		FROM @EmptyTable
	END
	ELSE
	BEGIN
		-- Region: fee
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
		SELECT d.PartyId, d.ProductId, d.Fee, @AmountTypeSoftwareFee
		FROM #AmountToCompany d
		-- End Region

		-- product dont have minfee
		INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
		(
			SELECT	td.PartyId,
					td.ProductId,
					SUM(td.AmountToCompany),
					@AmountTypeSoftwareFee
			FROM	#TempData td 
			WHERE	td.ProductId NOT IN (SELECT td2.ProductId FROM @InvoiceData td2)
			GROUP	BY td.PartyId, td.ProductId
		)

		-- Region: Discount
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate, Remark)
		SELECT d.PartyId, d.ProductId, d.Discount, @AmountTypeDiscount, d.DiscountRate, d.DiscountRemark
		FROM #AmountToCompany d WHERE d.Discount > 0
		-- End Region

		-- Region: Rebate
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate, Remark)
		SELECT d.PartyId, d.ProductId, Rebate, @AmountTypeRebate, d.RebateRate, d.RebateRemark
		FROM #AmountToCompany d
		-- End Region

		-- Region: Select data	
		DECLARE	@FinalResult TABLE(
				ProductId		INT,
				ProductCode		VARCHAR(100),
				ProductName		VARCHAR(500),
				Remark			NVARCHAR(4000),
				InvoiceAmount	MONEY,
				AmountType		TINYINT,
				Rate			MONEY,
				DeductMonthlyFees	MONEY,
				RemainingAmount	MONEY)

		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate,Remark)
		(
			SELECT	id.ProductId,
					CASE 
						WHEN id.ProductId = 0 THEN 'SB' 
						ELSE p.ProductPrefix
						END AS ProductCode,
					CASE 
						WHEN id.ProductId = 0 THEN 'Sportsbook' 
						ELSE p.ProductName
						END AS ProductName,
					CASE
						WHEN id.InvoiceAmount > 0 OR id.ProductId = 3 OR id.ProductId = @CBProductId OR id.ProductId = @COProductId THEN id.InvoiceAmount
						ELSE 0
					END AS InvoiceAmount,
					id.AmountType,
					id.Rate,
					id.Remark
			FROM	@InvoiceData id
					LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON id.ProductId = p.Productid
		)

		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate,Remark)
		(
			SELECT	-1,
					(	SELECT	f.ProductCode + ',' 
						FROM	@FinalResult f 
						WHERE f.AmountType = id.AmountType AND f.Rate=id.Rate FOR XML PATH('')) 
					AS ProductCode,
					(	SELECT	f.ProductName + ',' 
						FROM	@FinalResult f 
						WHERE f.AmountType = id.AmountType AND f.Rate=id.Rate FOR XML PATH('')) 
					AS ProductName,
					SUM(id.InvoiceAmount),
					id.AmountType,
					id.Rate,
					id.Remark
			FROM	@FinalResult id
			WHERE	id.AmountType > @AmountTypeSoftwareFee
			GROUP BY id.AmountType, id.Rate, id.Remark
		)	
		UPDATE	@FinalResult
		SET		ProductCode = LEFT(ProductCode, LEN(ProductCode) - 1),
				ProductName = LEFT(ProductName, LEN(ProductName) - 1)
		WHERE	ProductId = -1
		
		-- 10: debit note for return amf
		IF @InvoiceTypeId = 10
		BEGIN
			-- get AMF and prepayment
			SELECT SUM(ISNULL(Income,0) - ISNULL(Expense,0)) Amount, s.InvItemTypeId
			INTO #credit
			FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
			WHERE s.InvItemTypeId IN (3,5,7,21,22,23,24) 
				AND s.RefPartyId = @PartyId
				AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
				AND h.Environment = @Environment
			GROUP BY s.InvItemTypeId

			DECLARE @RemainingAmf MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeId IN (3,5,7,21)),0)
			DECLARE @Prepayment MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeId IN (22,23,24)),0)

			DELETE @FinalResult
			INSERT INTO @FinalResult(AmountType, RemainingAmount, InvoiceAmount) VALUES (1, @RemainingAmf, @Prepayment)
		END

		SELECT	f.ProductId,
				f.ProductCode,
				f.ProductName,
				f.InvoiceAmount,
				f.AmountType,
				f.Rate,
				f.DeductMonthlyFees,
				f.RemainingAmount,
				f.Remark
		FROM	@FinalResult f
		WHERE (@InvoiceTypeId != 3		--not rebate
				AND f.ProductId != -1	-- not summarized row
				AND (
						f.AmountType = @AmountTypeSoftwareFee OR	-- software data fee rows
						f.AmountType = @AmountTypeDiscount OR		-- discount rows
						f.AmountType = @DeductAgainstInvoice		-- deduct against invoice
					))
			OR (@InvoiceTypeId = 3 -- rebate
				AND f.ProductId = -1 AND f.AmountType = @AmountTypeRebate -- summarized rebate row
			)
			OR @InvoiceTypeId = 10
		ORDER BY f.AmountType, f.ProductId
	END

	SELECT @ErrCode = 0, @ErrMsg = ''

	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #TempDataCB
	DROP TABLE #AmountToCompany

END
GO