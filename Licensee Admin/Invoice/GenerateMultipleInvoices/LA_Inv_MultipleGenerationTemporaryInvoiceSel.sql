/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_MultipleGenerationTemporaryInvoiceSel]
	@BillerId				INT,
	@InvoiceGeneratingData	NVARCHAR(MAX),
	@FromDate				DATE,
	@ToDate					DATE,
	@Environment			VARCHAR(10)
AS	

/*	Header:
	Created: 2021.03.02 - Parsons
	Task : Support a function to export all invoices at once: Generate Multiple Temporary Invoice
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20210302@Parsons: Create new sp [#147006]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]

	Param's Explanation:
		@InvoiceGeneratingData:
		'<Root>
			<InvoiceGenerating>
				<InvoiceNumber>123</InvoiceNumber>
				<PartyId>1</PartyId>
				<InvoiceTypeShorten>S</InvoiceTypeShorten>
			</InvoiceGenerating>
		</Root>'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (16, 37) AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	SELECT  @ProductCodes = 'SB' + ISNULL(',' + @ProductCodes, '')

	DECLARE @FinalResult TABLE (PartyId INT, InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, BillerId INT, InvoiceType TINYINT, InvoicePath NVARCHAR(255), ProductCodes VARCHAR(MAX), LicensingFee MONEY, Discount MONEY, ExtraAmount MONEY, AdjustmentAmount MONEY, AdjustmentNote NVARCHAR(500))
	
	-- Region: Get Party Settings
	BEGIN
		DECLARE @InvoiceData TABLE (IndexNumber INT IDENTITY(1, 1), InvoiceNumber INT, PartyId INT, InvoiceTypeId SMALLINT, InvoiceTypeShorten VARCHAR(10))
		
		BEGIN TRY
			DECLARE @Party_XML XML = CONVERT(XML, @InvoiceGeneratingData)

			INSERT INTO @InvoiceData (InvoiceNumber, PartyId, InvoiceTypeShorten, InvoiceTypeId)
			SELECT InvoiceNumber, PartyId, InvoiceTypeShorten, CASE InvoiceTypeShorten WHEN 'S' THEN 1 WHEN 'R' THEN 3 WHEN 'H' THEN 6 END
			FROM (
				SELECT
					t.c.value('(InvoiceNumber/text())[1]', 'INT') AS InvoiceNumber
					,t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
					,t.c.value('(InvoiceTypeShorten/text())[1]', 'VARCHAR(10)') AS InvoiceTypeShorten
				FROM @Party_XML.nodes('Root/InvoiceGenerating') t(c)
			) a
			OPTION (OPTIMIZE FOR (@Party_XML = NULL))

			-- Remove duplicate data
			DELETE t
			FROM (
				SELECT PartyId, ROW_NUMBER() OVER(PARTITION BY PartyId, InvoiceTypeId ORDER BY InvoiceNumber) AS RN
				FROM @InvoiceData
			) t
			WHERE t.RN > 1
		END TRY
		BEGIN CATCH
			PRINT 'Wrong format XML'
		END CATCH

		DECLARE @PartySettings TABLE (PartyId INT, LicenseeId INT, PartyName VARCHAR(50), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50))
		INSERT INTO @PartySettings (PartyId, LicenseeId, PartyName, BaseCurrencyId, BaseCurrencyName, InvoiceLanguage)
		SELECT p.PartyId, p.OldRefId, p.PartyName, ISNULL(bc.BaseCurrencyId, 6), ISNULL(e.Code, 'EUR'), pd.InvoiceLanguage
		FROM (SELECT DISTINCT PartyId FROM @InvoiceData) i
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON p.PartyId = i.PartyId
			LEFT JOIN OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
			LEFT JOIN OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.ExchangeId = bc.BaseCurrencyId

		DECLARE @InvoiceSymbol NVARCHAR(20)
		SELECT TOP 1 @InvoiceSymbol = InvoiceSymbol
		FROM dbo.LA_InvoiceHeader WITH (NOLOCK)
		WHERE StatusId = 0 AND Environment = @Environment
			AND InvoiceType IN (1, 3, 6) -- Software Fee, Rebate, Hosting Fee
			AND BillerId = @BillerId
		ORDER BY CreatedDateTime DESC
		
		DECLARE @InvoiceSettings TABLE (IndexNumber INT, PartyId INT, BillerId INT, InvTypeId SMALLINT, ProductCodes VARCHAR(200), InvTemplateName VARCHAR(50), InvoiceSymbol NVARCHAR(20), InvoiceNumber INT)
		INSERT INTO @InvoiceSettings (IndexNumber, PartyId, BillerId, InvTypeId, InvTemplateName, InvoiceSymbol, InvoiceNumber, ProductCodes)
		SELECT d.IndexNumber, s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName, @InvoiceSymbol, d.InvoiceNumber
			, STUFF((SELECT ',' + CASE WHEN ls.ProductId = 0 THEN 'SB' ELSE ProductPrefix END
						FROM dbo.LA_InvoiceSetting ls WITH (NOLOCK)
							LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON ls.ProductId = p.ProductId
						WHERE s.InvTypeId = ls.InvTypeId AND s.FromPartyId = ls.FromPartyId AND s.ToPartyId = ls.ToPartyId
							AND ls.InvTypeId = 1 AND ls.ProductId IS NOT NULL
						FOR XML PATH('')), 1, 1, '') AS ProductCodes
		FROM @PartySettings ps
			INNER JOIN @InvoiceData d ON ps.PartyId = d.PartyId
			INNER JOIN dbo.LA_InvoiceSetting s WITH (NOLOCK) ON s.FromPartyId = ps.PartyId AND s.InvTypeId = d.InvoiceTypeId
			INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON s.InvTempId = t.InvTemplateId
		WHERE s.InvTypeId IN (1, 3, 6) AND s.ToPartyId = @BillerId
		GROUP BY d.IndexNumber, s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName, d.InvoiceNumber
	END
	-- End Region: Get Party Settings

	-- Region: Get Exchange
	BEGIN
		DECLARE @BaseCurrencies TABLE (RowId SMALLINT IDENTITY(1, 1), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
		CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, CurrencyCode	VARCHAR(10), BaseCurrencyId INT, BaseCurrencyRate FLOAT)
		
		INSERT INTO @BaseCurrencies (BaseCurrencyId, BaseCurrencyName)
		SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @PartySettings

		INSERT INTO #Exchange (ExchangeDate, ExchangeId, CurrencyCode, BaseCurrencyId, BaseCurrencyRate)
		SELECT e.ExchangeDate, e.ExchangeId, e.Code, bc.BaseCurrencyId, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.BaseCurrencyName) e
	END
	-- End Region: Get Exchange

	-- Region: Get hosting fee
	BEGIN
		DECLARE @HostingFee TABLE (PartyId INT, SettingType TINYINT, CurrencyId INT, NoOfDate INT, Amount MONEY, HostingFeesTypeId TINYINT, VCMFrom INT, VCMTo INT)
		INSERT INTO @HostingFee (PartyId, SettingType, CurrencyId, NoOfDate, Amount)
		SELECT PartyId, SettingType, CurrencyId, DATEDIFF(DAY, FromDate, ToDate) + 1, Amount
		FROM (
			SELECT s.FromParty AS PartyId, s.SettingType, d.Amount, d.BaseCurrencyId AS CurrencyId
				,CASE WHEN s.FromDate < @FromDate THEN @FromDate ELSE s.FromDate END AS FromDate
				,CASE WHEN s.ToDate > @ToDate THEN @ToDate ELSE s.ToDate END AS ToDate
				,ROW_NUMBER() OVER(PARTITION BY s.FromParty, s.SettingType ORDER BY s.FromDate DESC) AS RN
			FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
				LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
				LEFT JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON f.HostingFeesId = d.HostingFeesId AND f.HostingFeesTypeId = 1 -- Fixed
			WHERE @FromDate <= s.ToDate AND @ToDate >= s.FromDate
		) s
		WHERE s.RN = 1 AND DATEDIFF(DAY, FromDate, ToDate) >= 0

		/*
		-- for VCM
		IF EXISTS (SELECT 1 FROM @HostingFee WHERE HostingFeesTypeId = 2)
		BEGIN
			DECLARE @PartyServers TABLE (PartyId INT, ServerId VARCHAR(20))
			DECLARE @PeakConcurrentUsers TABLE (ServerId VARCHAR(20), LogDate DATETIME, Users INT)
			
			INSERT INTO @PartyServers (PartyId, ServerId)
			SELECT p.PartyId, LEFT(CONVERT(VARCHAR(20), s.ServerId), 3)
			FROM @PartySettings p
				INNER JOIN dbo.view_site_list ls WITH (NOLOCK) ON p.LicenseeId = ls.SiteId
				INNER JOIN bodb02.dbo.Site s WITH (NOLOCK) ON ls.IbcSiteId = s.SiteId

			DECLARE @ServerIds VARCHAR(MAX), @SQL VARCHAR(MAX)
			SELECT  @ServerIds = COALESCE(@ServerIds + ',' , '') + ServerId FROM @PartyServers
			
			SET @SQL = '
			SELECT LogDate, ServerId, Users
			FROM OPENQUERY(DBONUSER, ''	SELECT CONVERT(DATE, LogDate) AS LogDate, ServerId, MAX(Users) AS Users
										FROM (
											SELECT LogDate, LEFT(CONVERT(VARCHAR(20), ServerId), 3) AS ServerId, SUM(Users) AS Users
											FROM ON_USER.dbo.TotalOnline WITH (NOLOCK)
											WHERE LogDate >= ''''' + CONVERT(VARCHAR(10), @FromDate, 120) + '''''
												AND LogDate < ''''' + CONVERT(VARCHAR(10), DATEADD(DAY, 1, @ToDate), 120) + '''''
												AND LEFT(CONVERT(VARCHAR(20), ServerId), 3) IN (' + @ServerIds + ')
											UNION ALL
											SELECT LogDate, LEFT(CONVERT(VARCHAR(20), ServerId), 3) AS ServerId, SUM(Users) AS Users
											FROM ON_USER.dbo.TotalOnline_BK WITH (NOLOCK)
											WHERE LogDate >= ''''' + CONVERT(VARCHAR(10), @FromDate, 120) + '''''
												AND LogDate < ''''' + CONVERT(VARCHAR(10), DATEADD(DAY, 1, @ToDate), 120) + '''''
												AND LEFT(CONVERT(VARCHAR(20), ServerId), 3) IN (' + @ServerIds + ')
										) t
										GROUP BY CONVERT(DATE, LogDate), ServerId)'
			INSERT INTO @PeakConcurrentUsers (LogDate, ServerId, Users)
			EXEC (@SQL)
		END
		*/

		UPDATE h1
		SET h1.Amount = h1.Amount * ISNULL((1.0 * (h2.FeeDate - h2.WaiveDate) / h2.FeeDate), 1.0)
		FROM @HostingFee h1
			OUTER APPLY (
				SELECT TOP 1 h1.NoOfDate AS FeeDate, h2.NoOfDate AS WaiveDate
				FROM @HostingFee h2
				WHERE h1.PartyId = h2.PartyId AND h2.SettingType = 2
			) h2
		WHERE h1.SettingType = 1

		INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, LicensingFee)
		SELECT h.PartyId, ivs.BillerId, 6, h.Amount * e.BaseCurrencyRate
		FROM @HostingFee h
			INNER JOIN @PartySettings ps ON h.PartyId = ps.PartyId
			INNER JOIN @InvoiceSettings ivs ON h.PartyId = ivs.PartyId AND ivs.InvTypeId = 6 -- Hosting Fee
			INNER JOIN #Exchange e ON h.CurrencyId = e.ExchangeId AND ps.BaseCurrencyId = e.BaseCurrencyId AND e.ExchangeDate = @ToDate
			LEFT JOIN @FinalResult f ON h.PartyId = f.PartyId AND ivs.BillerId = f.BillerId AND f.InvoiceType = 6
		WHERE h.SettingType = 1 AND f.PartyId IS NULL
	END
	-- End Region: Get hosting fee

	-- Region: Get party's amount
	BEGIN
		DECLARE @SumByProducts TABLE (PartyId INT, ProductId INT, ProductCode VARCHAR(500), LicensingFee MONEY, ExtraAmount MONEY, Discount MONEY, Rebate MONEY)

		-- Region: Get amount to company, discount, rebate (only for some supported products)
		BEGIN
			CREATE TABLE #AmountToCompany (PartyId INT, ProductId INT, Fee MONEY, Discount MONEY, Rebate MONEY, IsChargedByMinFee BIT, IsChargedByGroupMinFee BIT)
			DECLARE @temp_PartyIds VARCHAR(MAX), @temp_BaseCurrencyId INT, @temp_BaseCurrencyName VARCHAR(10), @RowId SMALLINT = 1

			WHILE 1 = 1
			BEGIN
				SELECT @Temp_PartyIds = NULL, @temp_BaseCurrencyId = NULL, @temp_BaseCurrencyName = NULL
				SELECT @temp_BaseCurrencyId = BaseCurrencyId, @temp_BaseCurrencyName = BaseCurrencyName FROM @BaseCurrencies WHERE RowId = @RowId

				IF @temp_BaseCurrencyId IS NULL
					BREAK

				SELECT @temp_PartyIds = COALESCE(@temp_PartyIds + ',', '') + CAST(PartyId AS VARCHAR(20)) FROM @PartySettings WHERE BaseCurrencyId = @temp_BaseCurrencyId

				INSERT INTO #AmountToCompany(PartyId, ProductId, Fee, Discount, Rebate, IsChargedByMinFee, IsChargedByGroupMinFee)
				EXEC dbo.LA_AmountToCompanyByDiscountCurrencySel
					@FromDate			= @FromDate
					,@ToDate			= @ToDate
					,@PartyIds			= @temp_PartyIds
					,@ProductCodes		= @ProductCodes
					,@BaseCurrencyName	= @temp_BaseCurrencyName
					,@BaseCurrencyId	= @temp_BaseCurrencyId
					,@CurrencyId		= 0
				
				SET @RowId = @RowId + 1
			END
		END
		-- End Region: Get amount to company, discount, rebate (only for some supported products)

		-- Region: Get amount to company for remaining products
		BEGIN
			-- Region: Party charge info
			BEGIN
				DECLARE @PartyIds VARCHAR(MAX)
				SELECT  @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM @PartySettings

				DECLARE @PartyChargeInfo TABLE (ChargeId INT, ChargeType INT, PartyId INT, LicenseeId INT, ProductId INT, BettypeRef INT, FromDate DATE, ToDate DATE, Rate FLOAT)
				INSERT INTO @PartyChargeInfo (ChargeId, ChargeType, PartyId, LicenseeId, ProductId, BettypeRef, FromDate, ToDate, Rate)
				SELECT ChargeId, ChargeType, PartyId, LicenseeId, ProductId, Bettype, FromDate, ToDate, DI_Rate
				FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
				WHERE DI_Rate > 0

				-- Specific for CB
				DECLARE @MinCBDate DATE, @MaxCBDate DATE
				SELECT  @MinCBDate = MIN(FromDate), @MaxCBDate = MAX(ToDate) FROM @PartyChargeInfo WHERE ProductId = 15

				DECLARE @CBChargeRate TABLE (PartyId INT, LicenseeId INT, rptDate DATE, CommShareRate FLOAT, CashInShareRate FLOAT)
				;WITH CTE_rptDate AS (
					SELECT @MinCBDate AS rptDate
					UNION ALL SELECT DATEADD(DAY, 1, rptDate) FROM CTE_rptDate WHERE rptDate < @MaxCBDate
				)
				INSERT INTO @CBChargeRate (PartyId, LicenseeId, rptDate, CommShareRate, CashInShareRate)
				SELECT DISTINCT ISNULL(cr.PartyId, sr.PartyId), ISNULL(cr.LicenseeId, sr.LicenseeId), r.rptDate, ISNULL(cr.Rate, 0), ISNULL(sr.Rate, 0)
				FROM CTE_rptDate r
					LEFT JOIN @PartyChargeInfo cr ON r.rptDate BETWEEN cr.FromDate AND cr.ToDate AND cr.ProductId = 15 AND cr.ChargeType = 6
					LEFT JOIN @PartyChargeInfo sr ON r.rptDate BETWEEN sr.FromDate AND sr.ToDate AND sr.ProductId = 15 AND sr.ChargeType = 7
				WHERE cr.ProductId IS NOT NULL OR sr.ProductId IS NOT NULL
				OPTION (MAXRECURSION 0)

				DELETE @PartyChargeInfo WHERE ProductId = 15
			END
			-- End region: Party charge info

			-- Region: Get Win Loss Data
			BEGIN
				CREATE TABLE #TempData (
					LicenseeId INT, rptDate DATE, ProductId INT, BettypeRef INT DEFAULT(-1), CurrencyId INT
					,MemberWL MONEY DEFAULT(0), MemberComm MONEY DEFAULT(0), AgentWL MONEY DEFAULT(0), AgentComm MONEY DEFAULT(0)
					,Contribution MONEY DEFAULT(0), JackpotPrize MONEY DEFAULT(0), ExtraAmount MONEY DEFAULT(0), OddsSpread MONEY DEFAULT(0)
					,PayOut MONEY DEFAULT(0), CommShare MONEY DEFAULT(0), CashInShare MONEY DEFAULT(0)
				)

				CREATE TABLE #tmpResult (PartyId INT, ProductId INT, rptDate DATE, LicenseeAmount FLOAT, ExtraAmount FLOAT DEFAULT(0), IsApplyMinFee BIT DEFAULT (1))
				
				-- CO
				DECLARE @FDate SMALLDATETIME = @FromDate, @TDate SMALLDATETIME = @ToDate
				INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, MemberWL, PayOut)
				SELECT r.SiteId, CONVERT(DATE, r.WinlostDate) AS rptDate, 25, r.Currency
					,SUM(r.BuyBackAmt) AS MemberWL
					,SUM(r.TicketPayout - r.BuyBackAmt - r.BABuyBackAmt) AS Payout
				FROM bodb_LicenseeReport.dbo.rptLicCashoutSummary r WITH (NOLOCK)
				WHERE r.WinlostDate BETWEEN @FDate AND @TDate
					AND r.Currency <> 20
					AND r.RoleId = 1 -- Member
				GROUP BY r.SiteId, CONVERT(DATE, r.WinlostDate), r.Currency
	
				INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, BettypeRef, MemberWL, MemberComm, AgentWL, AgentComm, Contribution, JackpotPrize, ExtraAmount, OddsSpread, PayOut, CommShare, CashInShare)
				SELECT r.SiteId, r.rptDate, r.ProductId, r.CurrencyId
					,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
					,SUM(CASE WHEN (r.ProductId IN (32, 43, 42, 66) AND ISNULL(r.TicketType, 0) = 2) OR r.Bettype IN (902, 903, 904, 999, 4299, 4300, 4297, 4298, 1698, 1699, 1906, 3898, 3899) THEN 0 ELSE ISNULL(r.MemberWL, 0) END) AS MemberWL
					,SUM(ISNULL(r.CommissionP, 0)) AS MemberComm
					,SUM(ISNULL(r.GrossWL, 0)) AS AgentWL
					,SUM(ISNULL(r.CommissionA, 0)) AS AgentComm
					,SUM(CASE WHEN r.Bettype IN (4297, 1698, 3898) THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
					,SUM(CASE WHEN r.Bettype IN (4298, 1699, 3899) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
					,SUM(CASE WHEN r.Bettype IN (4300, 4299, 1906, 3150) OR (r.ProductId IN (32, 43, 42, 66) AND ISNULL(r.TicketType, 0) = 2) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS ExtraAmount
					,SUM(CASE WHEN r.Bettype = 999 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
					,SUM(CASE WHEN r.ProductId = 15 THEN ISNULL(r.Turnover, 0) - ISNULL(r.WinPrizeAmount, 0) - ISNULL(r.CashOutAmount, 0) ELSE 0 END) AS PayOut
					,SUM(CASE WHEN r.ProductId = 15 THEN CASE WHEN ISNULL(r.TicketType, 0) = 0 THEN ISNULL(r.Turnover, 0) ELSE ISNULL(r.ExtraAmount, 0) END ELSE 0 END) AS CommShare
					,SUM(CASE WHEN r.ProductId = 15 OR r.Bettype = 901 THEN ISNULL(r.BuyBackAmount, 0) ELSE 0 END) AS CashInShare
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
					LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
				WHERE r.rptDate BETWEEN @FromDate AND @ToDate
					AND r.StatusId NOT IN (-1, 101, 102, 103)
					AND r.CustomerCategory NOT IN (27, 28)
					AND r.CurrencyId <> 20
					AND r.ProductId <> 25 -- CO
				GROUP BY r.SiteId, r.rptDate, r.CurrencyId, r.ProductId
					,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END

				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount, ExtraAmount)
				SELECT ps.PartyId, t.ProductId, t.rptDate
					,SUM((CASE
							WHEN t.BettypeRef IN (1706, 3007) THEN 0
							WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
							WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
							WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
							ELSE (-MemberWL - Contribution) * ISNULL(cr.Rate, p.Rate) + PayOut + OddsSpread END
					) * e.BaseCurrencyRate) AS LicenseeAmount
					,SUM(CASE
							WHEN p.LicenseeId IS NULL THEN 0
							WHEN t.BettypeRef IN (1706, 3007) THEN -MemberWL * ISNULL(cr.Rate, p.Rate)
							ELSE (Contribution - JackpotPrize - ExtraAmount - CASE WHEN t.ProductId = 31 THEN (AgentComm + MemberComm) ELSE 0 END) * e.BaseCurrencyRate END
					) AS ExtraAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
					LEFT JOIN @CBChargeRate cp ON t.LicenseeId = cp.LicenseeId AND t.ProductId = 15 AND t.rptDate = cp.rptDate
					LEFT JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductId = p.ProductId AND t.BettypeRef = p.BettypeRef AND t.rptDate BETWEEN p.FromDate AND p.ToDate
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = p.ChargeId AND t.CurrencyId = cr.CurrencyId
				WHERE t.ProductId NOT IN (13, 37)
				GROUP BY ps.PartyId, t.ProductId, t.rptDate

				-- BT
				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount)
				SELECT p.PartyId, 13, t.rptDate, SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate) * e.BaseCurrencyRate) AS LicenseeAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 13
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
				WHERE t.ProductId IN (0, 3, 13)
				GROUP BY p.PartyId, t.rptDate

				-- SB Promotion
				INSERT INTO #tmpResult (PartyId, ProductId, rptDate, ExtraAmount)
				SELECT p.PartyId, 0, t.rptDate, -SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END * e.BaseCurrencyRate) AS ExtraAmount
				FROM #TempData t
					INNER JOIN @PartySettings ps ON t.LicenseeId = ps.LicenseeId
					INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
					INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate AND ps.BaseCurrencyId = e.BaseCurrencyId
				WHERE t.ProductId = 37
				GROUP BY p.PartyId, t.rptDate
			END
			-- End Region: Get Win Loss Data
		END
		-- End Region: Get amount to company for remaining products

		-- Region: Sum data by Product
		BEGIN
			;WITH CTE_Result AS (
				SELECT
					ISNULL(d.PartyId, r.PartyId) AS PartyId
					,ISNULL(d.ProductId, r.ProductId) AS ProductId
					,ISNULL(d.LicensingFee, r.LicensingFee) AS LicensingFee
					,ISNULL(r.ExtraAmount, 0) AS ExtraAmount
					,ISNULL(d.Discount, 0) AS Discount
					,ISNULL(d.Rebate, 0) AS Rebate
				FROM (
					SELECT PartyId, ProductId, SUM(Fee) AS LicensingFee, SUM(Discount) AS Discount, SUM(Rebate) AS Rebate
					FROM #AmountToCompany
					GROUP BY PartyId, ProductId
				) d
					FULL OUTER JOIN (
						SELECT PartyId, ProductId, SUM(LicenseeAmount) AS LicensingFee, SUM(ExtraAmount) AS ExtraAmount
						FROM #tmpResult
						GROUP BY PartyId, ProductId
					) r ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
			)
			INSERT INTO @SumByProducts (PartyId, ProductId, ProductCode, LicensingFee, ExtraAmount, Discount, Rebate)
			SELECT r.PartyId, r.ProductId, CASE WHEN r.ProductId = 0 THEN 'SB' ELSE p.ProductPrefix END
				,CASE WHEN r.LicensingFee > 0 OR jvp.PartyId IS NOT NULL OR r.ProductId IN (3, 15, 25, 31) THEN r.LicensingFee ELSE 0 END
				,r.ExtraAmount, r.Discount, r.Rebate
			FROM CTE_Result r
				LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
				LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON r.ProductId = p.ProductId

			INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, ProductCodes, LicensingFee, Discount, ExtraAmount)
			SELECT s.PartyId, ivs.BillerId, 1, ivs.ProductCodes, SUM(ROUND(s.LicensingFee, 2)), SUM(s.Discount), SUM(s.ExtraAmount)
			FROM @SumByProducts s
				INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes + ',' LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
				LEFT JOIN @FinalResult r ON ivs.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			WHERE r.PartyId IS NULL
			GROUP BY s.PartyId, ivs.BillerId, ivs.ProductCodes

			INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, LicensingFee)
			SELECT s.PartyId, ivs.BillerId, 3, -SUM(s.Rebate)
			FROM @SumByProducts s
				INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ivs.InvTypeId = 3 -- Rebate
				LEFT JOIN @FinalResult r ON ivs.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			WHERE r.PartyId IS NULL AND s.Rebate > 0
			GROUP BY s.PartyId, ivs.BillerId
		END
		-- End Region: Sum data by Product

		-- Region: Get AMF, Prepayment and AGPrepayment
		BEGIN
			DECLARE @InvItemTypes TABLE (InvItemTypeId SMALLINT, InvItemTypeName VARCHAR(50))
			INSERT INTO @InvItemTypes (InvItemTypeId, InvItemTypeName)
			-- AdvanceMinFee (AMF)
			SELECT InvItemTypeId, 'AdvanceMinFee' AS InvItemTypeName
			FROM (VALUES (3), (5), (7), (21)) AS t (InvItemTypeId)
			-- Prepayment
			UNION ALL
			SELECT InvItemTypeId, 'Prepayment' AS InvItemTypeName
			FROM (VALUES (22), (23), (24)) AS t (InvItemTypeId)
			-- AGPrepayment
			UNION ALL
			SELECT InvItemTypeId, 'AGPrepayment' AS InvItemTypeName
			FROM (VALUES (25), (26), (27)) AS t (InvItemTypeId)

			DECLARE @InvAmount TABLE (PartyId INT, RemainingAMF MONEY, RemainingAGPrepayment MONEY, RemainingPrepayment MONEY)
			INSERT INTO @InvAmount (PartyId, RemainingAMF, RemainingAGPrepayment, RemainingPrepayment)
			SELECT r.PartyId
				,SUM(CASE WHEN r.InvItemTypeName = 'AdvanceMinFee'	THEN r.Amount ELSE 0 END) AS RemainingAMF
				,SUM(CASE WHEN r.InvItemTypeName = 'AGPrepayment'	THEN r.Amount ELSE 0 END) AS RemainingAGPrepayment
				,SUM(CASE WHEN r.InvItemTypeName = 'Prepayment'		THEN r.Amount ELSE 0 END) AS RemainingPrepayment
			FROM (
				SELECT p.PartyId, t.InvItemTypeName, SUM(ISNULL(s.Income, 0) - ISNULL(s.Expense, 0)) AS Amount
				FROM @PartySettings p
					INNER JOIN dbo.LA_InvoiceStatement s WITH (NOLOCK) ON s.RefPartyId = p.PartyId
					INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
					INNER JOIN @InvItemTypes t ON s.InvItemTypeId = t.InvItemTypeId
				WHERE ISNULL(h.StatusId, 0) = 0 AND h.Environment = @Environment
				GROUP BY p.PartyId, t.InvItemTypeName
			) r
			GROUP BY r.PartyId

			-- AMF: SB only
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingAMF > 0)
			BEGIN
				DECLARE @FirstDate DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
				DECLARE @LastDate DATETIME = DATEADD(MONTH, DATEDIFF(MONTH, -1, @FromDate), -1)
				DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

				DECLARE @MinFee TABLE (PartyId INT, FeeTypeId TINYINT, FeeAmount MONEY, ProrateMinFee MONEY, FromDate DATETIME, ToDate DATETIME)

				-- Individual Min Fee: Base on Create Invoice function (not care exists on Group Min Fee)
				INSERT INTO @MinFee (PartyId, FeeTypeId, FeeAmount, FromDate, ToDate)
				SELECT m.PartyId, m.FeeTypeId, m.FeeAmount * e.BaseCurrencyRate
					,CASE WHEN @FromDate > FromDate THEN @FromDate ELSE FromDate END AS FromDate
					,CASE WHEN @ToDate < ToDate THEN @ToDate ELSE ToDate END AS ToDate
				FROM dbo.LA_MinFee m WITH (NOLOCK)
					INNER JOIN @InvAmount i ON m.PartyId = i.PartyId
					INNER JOIN @PartySettings ps ON m.PartyId = ps.PartyId
					LEFT JOIN #Exchange e ON m.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = ps.BaseCurrencyId AND e.ExchangeDate = @ToDate
				WHERE m.FeeTypeId IN (1, 2)
					AND m.FromDate <= @LastDate AND m.ToDate >= @FirstDate
					AND m.ProductId = 0 -- SB

				DELETE m
				FROM (
					SELECT PartyId, FeeTypeId, ROW_NUMBER() OVER(PARTITION BY PartyId, FeeTypeId ORDER BY FromDate DESC) AS RN
					FROM @MinFee
				) m
				WHERE RN > 1

				UPDATE m1
				SET m1.ProrateMinFee = (
							(
								SELECT TOP 1 m2.FeeAmount
								FROM @MinFee m2
								WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId
							) / (1.0 * @DaysInMonth / (DATEDIFF(DAY, m1.FromDate, m1.ToDate) + 1)))
				FROM @MinFee m1
				WHERE m1.FeeTypeId = 2

				UPDATE m1
				SET m1.ProrateMinFee = m1.FeeAmount / (1.0 * @DaysInMonth / (DATEDIFF(DAY, m1.FromDate, m1.ToDate) + 1))
										- ISNULL((
											SELECT SUM(m2.ProrateMinFee)
											FROM @MinFee m2
											WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId
											), 0)
				FROM @MinFee m1
				WHERE m1.FeeTypeId = 1

				DELETE @MinFee WHERE FeeTypeId = 2

				;WITH CTE_DeductedAMF AS (
					SELECT s.PartyId, ivs.BillerId, MIN(t.DeductedAMF) AS DeductedAMF
					FROM @SumByProducts s
						INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes + ',' LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
						INNER JOIN @InvAmount i ON s.PartyId = i.PartyId AND i.RemainingAMF > 0
						INNER JOIN @MinFee m ON s.PartyId = m.PartyId AND m.ProrateMinFee > 0
						CROSS APPLY (
							SELECT s.LicensingFee - s.Discount AS DeductedAMF
							UNION ALL SELECT i.RemainingAMF
							UNION ALL SELECT m.ProrateMinFee
						) t
					WHERE s.ProductId = 0 -- SB
						AND s.LicensingFee - s.Discount > 0
					GROUP BY s.PartyId, ivs.BillerId
				)
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - c.DeductedAMF
				FROM @FinalResult f
					INNER JOIN CTE_DeductedAMF c ON f.PartyId = c.PartyId AND f.BillerId = c.BillerId
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END

			-- AG Prepayment: AG Casino
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingAGPrepayment > 0)
			BEGIN
				;WITH CTE_DeductedAGPrepayment AS (
					SELECT s.PartyId, ivs.BillerId, MIN(t.DeductedAGPrepayment) AS DeductedAGPrepayment
					FROM @SumByProducts s
						INNER JOIN @InvoiceSettings ivs ON s.PartyId = ivs.PartyId AND ',' + ivs.ProductCodes + ',' LIKE '%,' + s.ProductCode + ',%' AND ivs.InvTypeId = 1 -- Software Fee
						INNER JOIN @InvAmount i ON s.PartyId = i.PartyId AND i.RemainingAGPrepayment > 0
						CROSS APPLY (
							SELECT s.LicensingFee - s.Discount AS DeductedAGPrepayment
							UNION ALL SELECT i.RemainingAGPrepayment
						) t
					WHERE s.ProductId = 10 -- AG Casino
						AND s.LicensingFee - s.Discount > 0
					GROUP BY s.PartyId, ivs.BillerId
				)
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - c.DeductedAGPrepayment
				FROM @FinalResult f
					INNER JOIN CTE_DeductedAGPrepayment c ON f.PartyId = c.PartyId AND f.BillerId = c.BillerId
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END

			-- Prepayment
			IF EXISTS (SELECT 1 FROM @InvAmount WHERE RemainingPrepayment > 0)
			BEGIN
				;WITH CTE_DeductedPrepayment AS (
					SELECT f.PartyId, f.BillerId, MIN(t.DeductedPrepayment) AS DeductedPrepayment
					FROM @FinalResult f
						INNER JOIN @InvAmount i ON f.PartyId = i.PartyId AND i.RemainingPrepayment > 0
						CROSS APPLY (
							SELECT f.LicensingFee - f.Discount AS DeductedPrepayment
							UNION ALL SELECT i.RemainingPrepayment
						) t
					WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
						AND f.LicensingFee - f.Discount > 0
					GROUP BY f.PartyId, f.BillerId
				)
				UPDATE f
				SET f.LicensingFee = f.LicensingFee - c.DeductedPrepayment
				FROM @FinalResult f
					INNER JOIN CTE_DeductedPrepayment c ON f.PartyId = c.PartyId AND f.BillerId = c.BillerId
				WHERE f.InvoiceType = 1 AND f.InvoiceHeaderId IS NULL
			END
		END
		-- End Region: Get AMF, Prepayment and AGPrepayment

		UPDATE @FinalResult SET LicensingFee = ISNULL(LicensingFee, 0) + ISNULL(ExtraAmount, 0) WHERE InvoiceType = 1 AND InvoiceHeaderId IS NULL
	END
	-- End Region: Get party's amount

	-- Region: Final Result
	BEGIN
		DECLARE @Result TABLE
		(
			RowIndex INT, IndexNumber INT, PartyId INT, PartyName VARCHAR(50), ItemType TINYINT, BillerId INT, BillerName NVARCHAR(50)
			,InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, InvoicePath NVARCHAR(256)
			,BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50), ProductCodes VARCHAR(MAX)
			,LicensingFee MONEY, Discount MONEY, Rebate MONEY, AdjustmentAmount MONEY, AdjustmentNote NVARCHAR(500)
		)

		INSERT INTO @Result
		(
			RowIndex, IndexNumber, PartyId, PartyName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
			,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate, AdjustmentAmount, AdjustmentNote
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY ivs.IndexNumber) AS RowIndex
			,ivs.IndexNumber
			,ps.PartyId
			,ps.PartyName
			,ivs.InvTypeId AS ItemType
			,ivs.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ivs.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ivs.InvoiceNumber) AS InvoiceNumber
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN ivs.InvTypeId = 1 THEN ivs.ProductCodes ELSE '' END AS ProductCodes
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN 0 ELSE r.LicensingFee END, 0)) AS LicensingFee
			,-SUM(ISNULL(r.Discount, 0)) AS Discount
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN r.LicensingFee ELSE 0 END, 0)) AS Rebate
			,SUM(ISNULL(r.AdjustmentAmount, 0)) AS AdjustmentAmount
			,ISNULL(r.AdjustmentNote, N'') AS AdjustmentNote
		FROM @PartySettings ps
			INNER JOIN @InvoiceSettings ivs ON ps.PartyId = ivs.PartyId
			LEFT JOIN @FinalResult r ON ps.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			INNER JOIN DBCUST.bodb_Licensee.dbo.LA_BillerInfo b WITH (NOLOCK) ON ivs.BillerId = b.PartyId
		GROUP BY
			ivs.IndexNumber
			,ps.PartyId
			,ps.PartyName
			,ivs.InvTypeId
			,ivs.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ivs.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ivs.InvoiceNumber)
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN ivs.InvTypeId = 1 THEN ivs.ProductCodes ELSE '' END
			,ISNULL(r.AdjustmentNote, N'')
	END
	-- End Region: Final Result

	-- Return data
	SELECT RowIndex, IndexNumber, PartyId, PartyName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
		,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate, AdjustmentAmount, AdjustmentNote
	FROM @Result

	DROP TABLE #AmountToCompany
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #tmpResult
END
GO