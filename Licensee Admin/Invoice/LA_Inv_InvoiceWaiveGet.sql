/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceWaiveGet] 
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyId		INT,
	@ProductCode	VARCHAR(100) = 'SB'
AS

/*	Header:
	Created: 2017-05-09 - @Scofield.Huynh
	DB: DBLIC.bodb_Licensee   
	Revisions: 
		+ 2017-05-09 @Scofield.Huynh: Create [#76132]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20201202@Mason: Change request Odds Spread [#142345]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PartyIds VARCHAR(20), @ProductId INT, @BaseCurrencyName VARCHAR(20) = 'EUR'
	SELECT  @PartyIds = CONVERT(VARCHAR(20), @PartyId), @ProductId = ProductId FROM dbo.LA_f_Products3rd(@ProductCode)

	SELECT @BaseCurrencyName = CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END
	FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
	WHERE bc.PartyId = @PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

	-- Get Charge Info
	DECLARE @FDate DATE, @TDate DATE
	SELECT  @FDate = MIN(FromDate), @TDate = MAX(ToDate)
	FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
	WHERE DI_Rate > 0

	DECLARE @DaysInMonth INT = DAY(DATEADD(MONTH, DATEDIFF(MONTH, -1, @FromDate), -1))

	DECLARE @FinalResult TABLE (FromDate DATE, ToDate DATE, MinFee MONEY, ProrateMinFee MONEY, IsGroupMinFee BIT, IsWaived BIT)
	INSERT INTO @FinalResult (FromDate, ToDate, MinFee, ProrateMinFee, IsGroupMinFee, IsWaived)
	SELECT FromDate, ToDate, MinFee, ProrateMinFee
		,CASE WHEN GroupMinFeeId > 0 THEN 1 ELSE 0 END AS IsGroupMinFee
		,CASE WHEN FeeTypeId = 2 THEN 1 ELSE 0 END AS IsWaived
	FROM dbo.LA_f_GetProrateMinFee(@PartyIds, @FromDate, @ToDate)
	WHERE ProductId = @ProductId

	DELETE @FinalResult WHERE ToDate < @FDate OR FromDate > @TDate
	
	UPDATE @FinalResult
	SET FromDate = CASE WHEN FromDate < @FDate THEN @FDate ELSE FromDate END
		,ToDate = CASE WHEN ToDate > @TDate THEN @TDate ELSE ToDate END
	WHERE FromDate < @FDate OR ToDate > @TDate

	INSERT INTO @FinalResult (FromDate, ToDate, IsGroupMinFee, IsWaived)
	SELECT @FDate, DATEADD(DAY, -1, MIN(FromDate)), 0, 1 FROM @FinalResult HAVING @FDate < MIN(FromDate)
	UNION ALL
	SELECT DATEADD(DAY, 1, MAX(ToDate)), @TDate, 0, 1 FROM @FinalResult HAVING @TDate > MAX(ToDate)

	DELETE @FinalResult WHERE IsWaived = 0 AND DATEDIFF(DAY, FromDate, ToDate) + 1 >= @DaysInMonth

	-- Get Licensing Fee
	IF EXISTS (SELECT 1 FROM @FinalResult)
	BEGIN
		
		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
		)
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCode
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrencyName

		IF EXISTS (SELECT 1 FROM @Result WHERE IsChargedByGroupMinFee = 0 AND ProductId = @ProductId)
			UPDATE @FinalResult SET ProrateMinFee = 0 WHERE IsGroupMinFee = 1

		IF EXISTS (SELECT 1 FROM @Result WHERE IsChargedByMinFee = 0 AND ProductId = @ProductId)
			UPDATE @FinalResult SET ProrateMinFee = 0 WHERE IsGroupMinFee = 0
	END

	-- Return Result
	SELECT
		CONVERT(DATETIME, FromDate) AS FromDate
		,CONVERT(DATETIME, ToDate) AS ToDate
		,@BaseCurrencyName AS CurrencyName
		,MinFee AS MinFeeAmount
		,ProrateMinFee AS MinFeeProrate
		,DATEDIFF(DAY, FromDate, ToDate) + 1 AS NumberOfDays
		,@DaysInMonth AS DaysInMonth, IsWaived
	FROM @FinalResult
	ORDER BY FromDate
END
GO