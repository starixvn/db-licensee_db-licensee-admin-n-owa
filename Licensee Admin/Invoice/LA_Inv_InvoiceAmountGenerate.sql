/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceAmountGenerate]
	@PartyId			INT,
	@BillerId			INT,
	@InvoiceTypeId		INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@ProductCodes		VARCHAR(100),
	@Environment		VARCHAR(50),
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT,
	@BaseCurrency		NVARCHAR(20)	= 'GBP'	OUTPUT,
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
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06 @Bravo.Tran: Invoice Amount - Generate
		+ 2015.09.22 @Bravo.Tran: Invoice Amount - Fix bug wrong Total amount under Discount.
		+ 2015.11.09 @Bravo.Tran: Invoice Amount - Enhance prorate min fee.
		+ 2016.06.27 @Bravo.Tran: Invoice Amount - Hosting Fess amount.
		+ 2016.07.19 @Bruce.Bui: Adding hosting fees extra info.
		+ 2016.09.27 @Bruce.Bui: Get MaxPCU case full month waive
		+ 2016.10.24 @Bruce.Bui: Add new discount type = 3
		+ 2016.09.27 @Bruce.Bui: Get MaxPCU case full month waive
		+ 2016.11.04 @Scofield.Huynh: Update for CB
		+ 2017.03.06 @bruce: include BA amount =0 [RedmindID: #72806]
		+ 2017.03.07 @Scofield: include amount = 0 for all products [RedmindID: #72806]
		+ 2017.04.03 @Scofield: update for Cashout [RedmindID: #73310]
		+ 2017.04.04 @Harper: using new sum table for Cashout Product [RedmindID: #73310]
		+ 2017.05.05 @Bruce: Correct Product name in Description [RedmindID: #75950]
		+ 2017.07.18 @Bruce: restructure invoice db [RedmindID: #79905]
		+ 2017.07.21 @Scofield: Update Amount Type [#79905]
		+ 2017.07.21 @Bruce: Calculate AMF amount [#76410]
		+ 2017.10.02 @Bruce: add environment to parameter list [#84038]
		+ 2017.10.27 @Bruce: show individual discount by product [#85256]		
		- 20171113@Bruce: Modified error message [RedmineID: #84163]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180110@Bruce: deduct against invoice [#87039]

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
	SET		@BaseCurrencyId = ISNULL((	SELECT TOP 1 opd.BaseCurrencyId
										FROM dbo.OAS_PartyDetail opd WITH(NOLOCK)	
										WHERE	opd.PartyID = @PartyId
									), 12)
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
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
	CREATE	TABLE #Exchange ( 
			ExchangeDate	DATE, 
			ExchangeID		INT, 
			CurrencyCode	VARCHAR(10), 
			Rate			FLOAT)	
	
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
								@HostingFeesExchangeName = e.CurrencyCode,
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
		DECLARE @ProductCodeString VARCHAR(100) = ''
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
						AND dh.DiscountGroupType = 2
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
	
	-- Region Party Group Assignment
	DECLARE @PartyGroup AS TABLE (PartyId INT)
	INSERT	INTO @PartyGroup(PartyId)
	(
		SELECT	PartyId 
		FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	PartyGroupId 
									FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
									WHERE	PartyId = @PartyId)
	)
	
	IF (SELECT COUNT(*) FROM @PartyGroup) = 0 -- Party dont have Party Group.
	BEGIN 
		INSERT INTO @PartyGroup(PartyId) VALUES(@PartyId)
	END
	-- End region
	
	-- Region: Get party charge rate info
	DECLARE	@PartyIdString VARCHAR(4000)
	SELECT	@PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM	@PartyGroup 
	
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
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId NOT IN (1, 15) --exclude RB, CB
	)
	
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
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE EXISTS(SELECT val FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'CB') AND
		FromParty = @PartyId AND ProductID = @CBProductId AND ChargeType IN (@CommChargeType,@CashInShareChargeType) AND (
		@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
		@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
		ci.FromDate BETWEEN @FromDate AND @ToDate OR
		ci.ToDate BETWEEN @FromDate AND @ToDate
	)	
	-- End Get ChargeInfo for CB
	
	-- End region
	
	-- Region: MinfeeGroup Date range	
		
	DECLARE @MinFeeGroup TABLE(
			FeeType			TINYINT,
			PartyId			INT,
			ProductId		INT,
			CurrencyId		INT,
			FeeAmount		MONEY,		
			FromDate		DATETIME,
			ToDate			DATETIME,
			MinFeeProrate	MONEY,
			WaivedAmount	MONEY,
			TotalAmount		MONEY,		
			MinFeeAmount	MONEY,
			AmountToCompany	MONEY,
			IsApplyMinFee	BIT)
	
	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT	mf.FeeTypeId, 
				mf.PartyId,
				mf.ProductId, 
				mf.CurrencyId,
				mf.FeeAmount,
				CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
				CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
		FROM	dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE   ((mf.FeeTypeId = 1 AND mf.CurrencyId = @BaseCurrencyId ) 
					OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId 
													FROM	dbo.LA_MinFee m WITH(NOLOCK)
													WHERE	m.FeeTypeId = 1 
															AND m.PartyId = mf.PartyId
															AND m.ProductId = mf.ProductId
															AND m.CurrencyId = @BaseCurrencyId
															AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) 
																OR (m.ToDate BETWEEN @FirstDate AND @LastDate) 
																OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
															)
													)
				)					
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
				)
				AND (mf.PartyId = @PartyId OR mf.PartyId IN (SELECT PartyId FROM @PartyGroup))
	)
	
	DELETE	FROM @MinFeeGroup
	WHERE	ProductID NOT IN (SELECT ProductId FROM @MinFeeGroup WHERE [@MinFeeGroup].PartyId = @PartyId)	
			OR (FeeType = 2 AND (FromDate > ToDate))
	-- End region
	
	-- Region: Get discount group info
	DECLARE @DiscountGroupHeader AS TABLE (
			DiscountGroupId		INT, 
			DiscountGroupType	TINYINT,
			PartyId				INT, 
			CurrencyId			INT, 
			FromDate			DATETIME, 
			ToDate				DATETIME)
		
	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@FromDate<= ToDate AND FromDate<=@ToDate
				AND dga.PartyID = @PartyId		
	)
	
	DELETE	FROM @DiscountGroupHeader
	WHERE	ToDate < (SELECT	MAX(ToDate)
					FROM	@DiscountGroupHeader
					WHERE	DiscountGroupType = 1)
			AND DiscountGroupType = 1
	DELETE	FROM @DiscountGroupHeader
	WHERE	ToDate < (SELECT	MAX(ToDate)
					FROM	@DiscountGroupHeader
					WHERE	DiscountGroupType = 2)
			AND DiscountGroupType = 2
	
	DECLARE @DiscountGroup AS TABLE(
			DiscountGroupId		SMALLINT,									
			DiscountGroupType	TINYINT,																		
			FromAmount			MONEY,
			ToAmount			MONEY,
			Rate				MONEY,
			PartyId				INT,		
			ProductId			TINYINT,
			BaseCurrency		INT)

	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency)	
	(
		SELECT	dg.DiscountGroupId, 
				dg.DiscountGroupType, 
				dgd.FromAmount, 
				dgd.ToAmount, 
				dgd.Rate,
				dg.PartyID,
				dgp.ProductId, 
				dg.CurrencyId
		FROM	@DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
				
		WHERE	dgp.ProductId IN ( SELECT DISTINCT ProductId FROM @PartyChargeInfo)			
	)
	-- End Region	
	
	-- Region: Validate the same base currency in ChargeInfo,MinFee & Discount/Rebate	
	DECLARE @BaseCurrencyCheck TABLE(
			Party INT, 
			Product INT, 
			FeeType INT, 
			BaseCurrencyCount INT, 
			NonBaseCurrencyCount INT)
	
	INSERT INTO @BaseCurrencyCheck
	SELECT	m.PartyId, 
			m.ProductId, 
			m.FeeTypeId,
			SUM(CASE WHEN m.CurrencyId = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount,
			SUM(CASE WHEN m.CurrencyId != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM	dbo.LA_MinFee m WITH(NOLOCK)
	WHERE	m.FeeTypeId = 1 AND m.PartyId IN (SELECT pg.PartyId FROM @PartyGroup pg)
			AND ((m.FromDate BETWEEN @FirstDate AND @LastDate) 
				OR (m.ToDate BETWEEN @FirstDate AND @LastDate) 
				OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
			)
	GROUP BY m.PartyId, m.ProductId, m.FeeTypeId	
	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Please check the Exchange settings of Payer''s minfee or minfee group. Exchange of minfee or minfees in group should be the same with Payer''s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END
		
	DELETE FROM @BaseCurrencyCheck	
	INSERT INTO @BaseCurrencyCheck(Party, Product, BaseCurrencyCount, NonBaseCurrencyCount)
	SELECT	d.PartyId, 
			d.ProductId,
			SUM(CASE WHEN d.BaseCurrency = @BaseCurrencyID THEN 1 ELSE 0 END) BaseCurrencyCount,
			SUM(CASE WHEN d.BaseCurrency != @BaseCurrencyID THEN 1 ELSE 0 END) NonBaseCurrencyCount
	FROM	@DiscountGroup d
	WHERE	d.DiscountGroupType = 1
	GROUP BY d.PartyId, d.ProductId
	
	IF EXISTS(SELECT 1 FROM @BaseCurrencyCheck WHERE BaseCurrencyCount = 0 AND NonBaseCurrencyCount > 0)
	BEGIN
		SELECT @ErrCode = 2, @ErrMsg = 'Please check the Exchange settings of Payer''s discount. Exchange of discount must be the same with Payer''s exchange.'
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @EmptyTable
		RETURN
	END
	
	DELETE FROM @DiscountGroup
	WHERE (BaseCurrency != @BaseCurrencyId AND DiscountGroupType = 1)
	
	-- End Region	
		
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
			IsApplyMinFee	BIT,
			LicenseeWinLossBase MONEY)
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
				LEFT JOIN dbo.Sport_Bettype_Reference r ON b.Bettype = r.Bettype
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
								END,
			LicenseeWinLossBase = -td.WinLoss * e.Rate
	FROM	#TempData td 
			INNER JOIN @PartyChargeInfo p 
				ON td.LicenseeId = p.LicenseeId 
				AND ((td.ProductId = p.ProductID AND td.ProductId NOT IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK)))
						OR 
					(td.ProductId = p.ProductID AND td.BettypeRef = p.BettypeRef AND td.ProductId IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK))))
				AND td.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID	
		
	UPDATE  t
	SET		t.IsApplyMinFee = 0
	FROM	#TempData t INNER JOIN @MinFeeGroup m ON t.rptDate BETWEEN m.FromDate AND m.ToDate
			AND t.ProductId = m.ProductId
			AND t.PartyId = m.PartyId
	WHERE	m.FeeType=2
	-- End region	
	
	-- Region: Get Amount By Product CB
	CREATE TABLE #TempDataCB (
		rptDate				DATETIME,
		LicenseeId			INT,
		PartyId				INT,
		ProductId			INT,
		CurrencyId			INT,
		Turnover			MONEY,
		TurnoverExchanged	MONEY,
		WinningPrize		MONEY,
		CashOut				MONEY,
		CommisionShare		MONEY,
		CashInShare			MONEY,
		CashInAmount		MONEY
	)
		
	INSERT INTO #TempDataCB (rptDate, LicenseeId, PartyId, ProductId, CurrencyId, Turnover, WinningPrize, CashOut, CashInAmount)
	SELECT	rptDate,
			b.SiteID,
			cb.PartyId,
			b.ProductId,
			CurrencyId,
			SUM(Turnover) Turnover,
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
	SET CommisionShare = td.Turnover * cm.Rate, CashInShare = td.CashInAmount * ci.Rate
	FROM #TempDataCB td
	JOIN @PartyChargeInfo AS cm ON cm.ProductID = @CBProductId AND cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
	JOIN @PartyChargeInfo AS ci ON cm.ProductID = @CBProductId AND ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany, LicenseeWinLossBase)
	SELECT LicenseeId, PartyId, rptDate, CurrencyId, ProductId, (Turnover - WinningPrize - Cashout - CommisionShare - CashInShare) * e.Rate, 0
	FROM #TempDataCB tcb
	INNER JOIN #Exchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID	
	-- End region: Get Amount By Product CB
	
	-- Region: Get Amount By Product CO	
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany, LicenseeWinLossBase)
	(
		SELECT
			d.LicenseeId,			
			d.PartyId,
			d.Winlostdate,
			d.Currency,
			@COProductId,
			(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate AS AmountToCompany,
			0				
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
	
	-- Region: Check min fee group			
	--- calculate waived prorate (*)
	UPDATE	amf
	SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
								FROM	@MinFeeGroup mfg
								WHERE	mfg.FeeType = 1
										AND mfg.PartyId = amf.PartyId
										AND mfg.ProductId = amf.ProductId)
							/ @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)	
	FROM	@MinFeeGroup amf
	WHERE	FeeType = 2
	
	--- sum amount under waived	
	UPDATE	amf	
	SET		amf.WaivedAmount = ISNULL((	SELECT	SUM(td.AmountToCompany)							
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND amf.ProductId = td.ProductId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 2
			
	--- calculate min fee prorate (fee amount in month - waived amount (*)
	UPDATE	amf
	SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) - 
										ISNULL((SELECT	SUM(f.MinFeeProrate)							
												FROM	@MinFeeGroup f
												WHERE	f.FeeType = 2
														AND amf.PartyId = f.PartyId
														AND amf.ProductId = f.ProductId), 0), 2),
			amf.WaivedAmount =  ISNULL((SELECT	CASE WHEN SUM(f.WaivedAmount) < 0 THEN 0 ELSE SUM(f.WaivedAmount) END
										FROM	@MinFeeGroup f
										WHERE	f.FeeType = 2
												AND amf.PartyId = f.PartyId
												AND amf.ProductId = f.ProductId), 0),	
			amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)							
										FROM	#TempData td 
										WHERE	amf.PartyId = td.PartyId
												AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
												AND td.IsApplyMinFee IS NULL
												AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	--- sum min fee amount
	UPDATE	amf
	SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	
	DECLARE @TotalMinFees TABLE(
		ProductId			INT,
		TotalMinFee			MONEY,
		TotalMinFeeAmount	MONEY
	)
	INSERT	INTO @TotalMinFees(ProductId, TotalMinFee)
	SELECT	mf.ProductId,
			SUM(MinFeeProrate)
	FROM	@MinFeeGroup mf
	WHERE	mf.FeeType = 1
	GROUP BY mf.ProductId
	
	UPDATE	t
	SET		TotalMinFeeAmount = ISNULL((	SELECT	SUM(mf.MinFeeAmount)
											FROM	@MinFeeGroup mf
											WHERE	mf.MinFeeAmount > 0
													AND FeeType = 1
													AND mf.ProductId = t.ProductId), 0)
	FROM	@TotalMinFees t
			
	--- calculate amount to company
	UPDATE	amf
	SET		amf.AmountToCompany =	CASE 
										WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
											THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									END,
			amf.IsApplyMinFee	=	CASE 
										WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
											THEN 1
										ELSE 0
									END
	FROM	@MinFeeGroup amf INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId
	WHERE	amf.FeeType = 1

	DECLARE @InvoiceData	TABLE(
			PartyId			INT,
			ProductId		INT, 
			InvoiceAmount	MONEY, 
			AmountType		TINYINT,
			Rate			MONEY)
		
	IF @InvoiceTypeId = @InvoiceTypeHostingFeesId
	BEGIN 
		DECLARE @IsApplyMinFee BIT = ISNULL((SELECT TOP 1 IsApplyMinFee FROM @MinFeeGroup WHERE PartyId = @PartyId AND FeeType=1),0)

		-- Apply Min fee => Not waived
		-- No Min fee => waived
		SET @IsWaived = (CASE WHEN @IsApplyMinFee = 1 THEN 0 ELSE 1 END)

		IF @IsWaived = 0 AND @FeesType = 2 -- VCM and not waive then re-calculate max PCU
		BEGIN
			SET @HostingFeesMaxPCU =ISNULL((SELECT MAX(TotalUser) FROM @CurrentUser),0)
			
			DELETE @EmptyTable

			INSERT INTO @EmptyTable
			SELECT p.Productid, p.ProductPrefix, s.ProductName, 0, d.Amount * e.Rate, @AmountTypeMonthlyHostingFee
			FROM @Settings s INNER JOIN dbo.Product3rd p ON s.ProductName = p.ProductName
				INNER JOIN dbo.LA_HostingFeesDetail d ON s.FeesId = d.HostingFeesId AND @HostingFeesMaxPCU BETWEEN d.VCMFrom AND d.VCMTo
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
		INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
		(
			SELECT	amf.PartyId, 
					amf.ProductId, 
					SUM(amf.AmountToCompany), 
					@AmountTypeSoftwareFee
			FROM	@MinFeeGroup amf
			WHERE	amf.PartyId = @PartyId
					AND amf.FeeType = 1
			GROUP	BY amf.PartyId, amf.ProductId
		)
	
		INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
		(
			SELECT	td.PartyId, 
					td.ProductId, 
					SUM(td.AmountToCompany), 
					@AmountTypeSoftwareFee
			FROM	#TempData td 
			WHERE	td.PartyId = @PartyId AND td.ProductId NOT IN (SELECT td2.ProductId FROM @MinFeeGroup td2)
			GROUP	BY td.PartyId, td.ProductId		
		)
		-- End region
	
		-- Region: Apply Discount
		DECLARE @TotalAmountDiscount MONEY = (	SELECT SUM(CASE WHEN i.InvoiceAmount < 0 THEN 0 ELSE i.InvoiceAmount END) 
												FROM @InvoiceData i 
												WHERE i.ProductId IN (SELECT ProductId FROM @DiscountGroup d WHERE d.DiscountGroupType = 1))
		DELETE	FROM @DiscountGroup
		WHERE	@TotalAmountDiscount NOT BETWEEN [@DiscountGroup].FromAmount AND [@DiscountGroup].ToAmount
				AND [@DiscountGroup].DiscountGroupType = 1
	
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate)
		(
			SELECT	iv.PartyId, iv.ProductId, iv.InvoiceAmount * dg.Rate AS InvoiceAmount, @AmountTypeDiscount, dg.Rate
			FROM	@InvoiceData iv INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
			WHERE	dg.DiscountGroupType = 1
		)	
		-- End Region

		-- discount by winloss
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate)
		(
			SELECT t.PartyId, t.ProductId, SUM(t.LicenseeWinLossBase * d.Rate), @AmountTypeDiscount, d.Rate
			FROM #TempData t
			INNER JOIN @DiscountGroup d ON d.ProductId = t.ProductId  AND d.DiscountGroupType = 3 AND t.PartyId=d.PartyId
			GROUP BY t.PartyId, t.ProductId, d.Rate
		)
		--end discount by winloss

		-- Region: Apply Rebate
		INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate)
		(
			SELECT	iv.PartyId, 
					iv.ProductId, 
					(iv.InvoiceAmount - ISNULL((SELECT	SUM(i.InvoiceAmount)
												FROM	@InvoiceData i
												WHERE	i.AmountType = @AmountTypeDiscount
														AND i.ProductId = iv.ProductId), 0))
						* dg.Rate AS InvoiceAmount, 
					@AmountTypeRebate, 
					dg.Rate
			FROM	@InvoiceData iv 
					INNER JOIN @DiscountGroup dg ON iv.ProductId=dg.ProductId
			WHERE	dg.DiscountGroupType = 2
					AND iv.AmountType = @AmountTypeSoftwareFee
		)
	
		-- End Region

		-- Region: Select data	
		DECLARE	@FinalResult TABLE(
				ProductId		INT,
				ProductCode		VARCHAR(100),
				ProductName		VARCHAR(500),
				InvoiceAmount	MONEY,
				AmountType		TINYINT,
				Rate			MONEY,
				AmfAmount		MONEY,
				RemainingAmf	MONEY)

		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate)
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
					id.Rate
			FROM	@InvoiceData id  
					LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON id.ProductId = p.Productid
		)

		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate)
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
					id.Rate
			FROM	@FinalResult id
			WHERE	id.AmountType > @AmountTypeSoftwareFee
			GROUP BY id.AmountType, id.Rate
		)	
		UPDATE	@FinalResult
		SET		ProductCode = LEFT(ProductCode, LEN(ProductCode) - 1),
				ProductName = LEFT(ProductName, LEN(ProductName) - 1)
		WHERE	ProductId = -1

		DECLARE @RemainingAmf MONEY = ISNULL((
			SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
			FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
			WHERE s.InvItemTypeId IN (3,5,7,21) 
				AND s.RefPartyId = @PartyId
				AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
				AND h.Environment = @Environment
		),0)

		-- InvoiceType Software: 1
		IF @InvoiceTypeId = 1			
		BEGIN
			-- insert zero amount
			INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, InvoiceAmount, AmountType)
			SELECT pd.ProductID, pd.ProductPrefix, pd.ProductName, 0, @AmountTypeSoftwareFee
			FROM (SELECT DISTINCT pci.ProductID 
				FROM @PartyChargeInfo pci
				LEFT JOIN @FinalResult r ON pci.ProductID = r.ProductId
				WHERE r.ProductId IS NULL) p
			JOIN dbo.LA_f_Products3rd('') pd ON p.ProductID = pd.ProductID

			-- insert amf
			IF @RemainingAmf > 0 
			BEGIN
				DECLARE @ProgratedMinfee MONEY = ISNULL((
					SELECT TOP 1 MinFeeProrate
					FROM @MinFeeGroup
					WHERE PartyId = @PartyId AND FeeType = 1 AND ProductId = 0
				),0)
				DECLARE @SBAfterDiscount MONEY = ISNULL((
					SELECT SUM(CASE WHEN AmountType = 1 THEN InvoiceAmount ELSE -InvoiceAmount END)
					FROM @FinalResult
					WHERE ProductId = 0 AND AmountType IN (1,4) -- 1: Software fee, 4: discount
				),0)
				DECLARE @AmfAmount MONEY = (CASE WHEN @RemainingAmf < @ProgratedMinfee THEN @RemainingAmf ELSE @ProgratedMinfee END)
				SET @AmfAmount = (CASE WHEN @AmfAmount < @SBAfterDiscount THEN @AmfAmount ELSE @SBAfterDiscount END)
				SET @AmfAmount = (CASE WHEN @AmfAmount < 0 THEN 0 ELSE @AmfAmount END)

				UPDATE @FinalResult SET AmfAmount = @AmfAmount, RemainingAmf = @RemainingAmf - @AmfAmount
				WHERE AmountType = 1 AND ProductId = 0 -- SB
			END

			-- deduct against invoice
			DECLARE @Prepayment MONEY = ISNULL((
				SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
				FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
				INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
				WHERE s.InvItemTypeId IN (22,23,24)
					AND s.RefPartyId = @PartyId
					AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
					AND h.Environment = @Environment
			),0)

			DECLARE @TotalAmount MONEY = (
				SELECT SUM((CASE WHEN AmountType=@AmountTypeDiscount THEN -InvoiceAmount ELSE InvoiceAmount END) - ISNULL(AmfAmount,0))
				FROM @FinalResult
				WHERE ProductId != -1	-- not summarized row
					AND AmountType IN (@AmountTypeSoftwareFee, @AmountTypeDiscount)
			)

			IF @Prepayment>0 AND @TotalAmount>0
			BEGIN
				DECLARE @RemainingPrepayment MONEY = @Prepayment - @TotalAmount
				INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmf)
				VALUES(0,'','',@DeductAgainstInvoice,
					CASE WHEN @RemainingPrepayment >=0 THEN -@TotalAmount ELSE -@Prepayment END,
					CASE WHEN @RemainingPrepayment >=0 THEN @RemainingPrepayment ELSE 0 END)
			END
		END

		-- 10: debit note for return amf
		IF @InvoiceTypeId = 10
		BEGIN
			DELETE @FinalResult
			INSERT INTO @FinalResult(AmountType, RemainingAmf) VALUES (1, @RemainingAmf)
		END

		SELECT	f.ProductId,
				f.ProductCode,
				f.ProductName,
				f.InvoiceAmount,
				f.AmountType,
				f.Rate,
				f.AmfAmount,
				f.RemainingAmf
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

END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceAmountGenerate] TO bodbAdminNet
GO
