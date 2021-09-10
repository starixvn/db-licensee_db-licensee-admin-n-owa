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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PartyIds VARCHAR(20), @ProductId INT, @BaseCurrencyName VARCHAR(20) = 'EUR'
	SELECT  @PartyIds = CONVERT(VARCHAR(20), @PartyId), @ProductId = ProductId FROM dbo.LA_f_Products3rd(@ProductCode)

	SELECT @BaseCurrencyName = e.Code
	FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
	WHERE bc.PartyId = @PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

	-- Get Charge Info
	DECLARE @ChargeInfo TABLE (FromDate DATE, ToDate DATE)
	INSERT INTO @ChargeInfo (FromDate, ToDate)
	SELECT DISTINCT FromDate, ToDate
	FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
	WHERE DI_Rate > 0

	-- Get Licensing Fee
	BEGIN
		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
		)
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCode
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrencyName
	END

	-- Get Min Fee: in case Licensing Fee is charged by min fee/group min fee
	DECLARE @FinalResult TABLE (FromDate DATE, ToDate DATE, MinFee MONEY, ProrateMinFee MONEY, IsWaived BIT)

	IF EXISTS (SELECT 1 FROM @Result WHERE IsChargedByGroupMinFee = 1 OR IsChargedByMinFee = 1)
	BEGIN
		INSERT INTO @FinalResult (FromDate, ToDate, MinFee, ProrateMinFee, IsWaived)
		SELECT FromDate, ToDate, MinFee, ProrateMinFee
			,CASE WHEN FeeTypeId = 2 THEN 1 ELSE 0 END AS IsWaived
		FROM dbo.LA_f_GetProrateMinFee (@PartyIds, @FromDate, @ToDate)
		WHERE ProductId = @ProductId AND IsPrimary = 1
	END

	DECLARE @DaysInMonth INT = DAY(DATEADD(MONTH, DATEDIFF(MONTH, -1, @FromDate), -1))

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
	WHERE IsWaived = 1 OR DATEDIFF(DAY, FromDate, ToDate) + 1 < @DaysInMonth
	ORDER BY FromDate
END
GO