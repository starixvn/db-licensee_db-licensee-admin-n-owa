/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_RebateWorksheetSel]
	@PartyId	INT
	,@FromDate	SMALLDATETIME
	,@ToDate	SMALLDATETIME
AS

/*	Created: 20170417@Bruce
	Task: Rebate worksheet [#76133]
	DB: bodb_licensee

	Revision:
	  - 20170710@bruce: include CO, CB, BA [#79741]
	  - 20171220@Parsons: increase length for variables [#88197]
	  - 20180126@Bruce: Exclude Exchange-BX [#87754]
	  - 20180419@Scofield: update CB for FreePlay [#93907]
	  - 20180716@bruce: add new group TEST for credit [#98126]
	  - 20180712@Bruce: Enhance Manage Discount group [#94282]
	  - 20200412@Parsons: Integrate SA Gaming [#129276]
	  - 20200427@Parsons: Intergrate IBCBet Win loss [#131165]
	  - 20200805@Parsons: Show net amount for PP in summary sheet [#138932]
	  - 20201103@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
	  - 20201216@Parsons: Saba.club - Offer Freebet tickets [#141423]
	  - 20201228@Parsons: Should include SBC & CC negative amount [#141357]
	  - 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
	  - 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
	  - 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
	  - 20210405@Parsons: Handle negative amount for CardClub product [#FeatureID 152089]
	  - 20210306@Danny: Add AE sexy data to Extra Amount [#152141]
	  - 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
	  - 20210916@Percy: Return Products applied rebate setting only [RedmineID: #159580]
	  - 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
	  - 20220210@Percy: Support Tier Rebate [RedmineID: #163495]
	  - 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate, @BaseCurrency VARCHAR(10) = 'EUR' -- default

	SELECT TOP 1 @BaseCurrency = Code
	FROM dbo.OAS_PartyBaseCurrency p WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE p.PartyID = @PartyId AND p.FromDate <= @TDate AND p.ToDate >= @FDate
	ORDER BY p.ToDate DESC
	
	-- products
	DECLARE @Products TABLE (ProductId INT, ProductCode VARCHAR(20))
	INSERT @Products (ProductId, ProductCode)
	SELECT p.ProductId, p.ProductPrefix
	FROM (
		SELECT p.ProductId, ROW_NUMBER() OVER(PARTITION BY p.ProductId ORDER BY h.ToDate DESC) AS RN
		FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
		WHERE a.PartyId = @PartyId
			AND h.DiscountGroupType IN (2, 12, 22) -- rebate
			AND h.FromDate <= @TDate AND h.ToDate >= @FDate
			AND p.ProductId NOT IN (1, 23, 13, 14, 17, 31) -- exclude RB, bettrade, NG2, MGCLC, MGCRNG, BX
	) r
		INNER JOIN dbo.LA_f_Products3rd('') p ON r.ProductId = p.ProductId
	WHERE r.RN = 1
		AND EXISTS (
			SELECT 1
			FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			WHERE c.FromParty = @PartyId AND c.ProductId = p.ProductId
				AND c.FromDate <= @TDate AND c.ToDate >= @FDate
				AND c.ToParty IN (1, 9, 11, 98) -- Licensee to house
				AND c.ChargeType NOT IN (2, 3) -- old charge type
		)

	-- Get Licensing Fee/Rebate data
	DECLARE @ProductCodes VARCHAR(MAX), @PartyIds VARCHAR(20) = CAST(@PartyId AS VARCHAR(20))
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM @Products

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
	)

	IF ISNULL(@ProductCodes, '') <> ''
	BEGIN
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrency

		DELETE @Result WHERE ProductId = 37
	END

	-- Total
	DECLARE @Remark NVARCHAR(4000), @TotalRebate MONEY, @TotalAmount MONEY
	SELECT @Remark = MAX(RebateRemark)
		,@TotalRebate = SUM(Rebate)
		,@TotalAmount = SUM(LicensingFee + ExtraAmount - Discount)
	FROM @Result

	SELECT @Remark = ISNULL(@Remark, N''), @TotalRebate = ISNULL(@TotalRebate, 0), @TotalAmount = ISNULL(@TotalAmount, 0)

	SELECT @Remark AS Remark, @ToDate AS ReportDate, @BaseCurrency AS CurrencyName, @TotalRebate AS TotalRebate, @TotalAmount AS TotalAmount

	-- Detail
	SELECT ProductId, LicensingFee - Discount AS AmountToCompany
	FROM @Result
END
GO