/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
	  - 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
	  - 20221213@Danny: Change fomular Calculate rebate base on Licensee Fee [RedmineID: #181546]
	  - 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
	  - 20230223@Danny: Integrate Casino promotion [#194808]
	  - 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
	  - 20241007@Sally: Support Odds Boost Voucher [#209884]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate, @BaseCurrency VARCHAR(10)

	DECLARE @CutOff_RebateOnLicfee  DATE = '2022-11-01'

	SELECT TOP 1 @BaseCurrency = CASE WHEN Code = 'UST' THEN 'USDT' ELSE Code END
	FROM dbo.OAS_PartyBaseCurrency p WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE p.PartyID = @PartyId AND p.FromDate <= @TDate AND p.ToDate >= @FDate
	ORDER BY p.ToDate DESC
	
	-- products
	DECLARE @Products TABLE (ProductId INT, ProductCode VARCHAR(20), RebateType TINYINT)
	INSERT @Products (ProductId, ProductCode, RebateType)
	SELECT p.ProductId, p.ProductPrefix, r.DiscountGroupType
	FROM (
		SELECT p.ProductId, h.DiscountGroupType, ROW_NUMBER() OVER(PARTITION BY p.ProductId, h.DiscountGroupType ORDER BY h.ToDate DESC) AS RN
		FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
		WHERE a.PartyId = @PartyId
			AND h.DiscountGroupType IN (2, 22) -- rebate on WL & Fee
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
				AND c.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z ) -- Licensee to house
				AND c.ChargeType NOT IN (2, 3) -- old charge type
		)

	-- Get Licensing Fee/Rebate data
	DECLARE @ProductCodes VARCHAR(MAX), @PartyIds VARCHAR(20) = CAST(@PartyId AS VARCHAR(20))
	
	;WITH CTE_Product AS (SELECT DISTINCT ProductCode FROM @Products)
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

	SELECT @ProductCodes = @ProductCodes +',SPR(CS)'
	WHERE EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value <> 'SB')

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, LicenseeWL MONEY, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000), OddsBoostBonus MONEY
	)

	DECLARE @Result_37 TABLE --ProductID = 37
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, LicenseeWL MONEY, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
	)

	IF ISNULL(@ProductCodes, '') <> ''
	BEGIN
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrency
			,@IncludeTierRebate = 0
			,@LicensingFeeTypeIds = '0,11,13,14' -- 11 = Licensee WL, 14 = Odds Boost Adjustment
		
		--Get data Odds Boost Bonus
		IF EXISTS(SELECT 1 FROM @Result WHERE ProductId = 0 AND LicensingFeeTypeId = 14)
		BEGIN
			UPDATE r 
			SET r.OddsBoostBonus = ISNULL(r14.ExtraAmount, 0)
			FROM @Result r
				INNER JOIN @Result r14 ON r.PartyId = r14.PartyId AND r.ProductId = r14.ProductId AND r14.LicensingFeeTypeId = 14								
			WHERE r.ProductId = 0 
				AND r.LicensingFeeTypeId = 0 			

			DELETE @Result WHERE LicensingFeeTypeId = 14
		END

		INSERT INTO @Result_37
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		SELECT PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		FROM @Result  WHERE ProductId = 37

		DELETE @Result WHERE ProductId = 37

		UPDATE r
		SET r.LicenseeWL = CASE WHEN t.ExtraAmount < 0 THEN 0 ELSE t.ExtraAmount END
		FROM @Result r
			INNER JOIN @Result t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
		WHERE r.LicensingFeeTypeId = 0 AND t.LicensingFeeTypeId = 11

		DELETE @Result WHERE LicensingFeeTypeId = 11
	END

	-- Total
	IF EXISTS (SELECT TOP 1 1 FROM @Result WHERE ProductId = -37)
		INSERT INTO @Products(ProductId, ProductCode, RebateType) VALUES (-37, 'SPR(CS)', 2) --rebate on LicFee

	DECLARE @Remark NVARCHAR(4000), @TotalRebate MONEY, @TotalAmount MONEY
	SELECT @Remark = MAX(r.RebateRemark)
		,@TotalRebate = SUM(r.Rebate)
		,@TotalAmount = SUM(CASE WHEN r.LicensingFeeTypeId = 13 THEN -r.ExtraAmount
										 WHEN p.RebateType = 2 THEN 
											CASE WHEN (r.LicensingFee + r.ExtraAmount - r.Discount 
														- CASE WHEN @FDate >= @CutOff_RebateOnLicfee THEN ISNULL(r_37.GrossLicensingFee,0) ELSE 0 END
														- ISNULL(r.OddsBoostBonus, 0)
														) < 0 THEN 0 
												ELSE r.LicensingFee + r.ExtraAmount - r.Discount 
														- CASE WHEN @FDate >= @CutOff_RebateOnLicfee THEN ISNULL(r_37.GrossLicensingFee,0) ELSE 0 
														- ISNULL(r.OddsBoostBonus, 0)
												END 
										END 
									ELSE r.LicenseeWL END)
	FROM @Result r
		INNER JOIN @Products p ON r.ProductId = p.ProductId
		LEFT JOIN @Result_37 r_37 ON r.PartyId = r_37.PartyId AND r.ProductId = 0  AND r_37.LicensingFeeTypeId = 0 AND r.LicensingFeeTypeId = 0

	SELECT @Remark = ISNULL(@Remark, N''), @BaseCurrency = ISNULL(@BaseCurrency, ''), @TotalRebate = ISNULL(@TotalRebate, 0), @TotalAmount = ISNULL(@TotalAmount, 0)

	SELECT @Remark AS Remark, @ToDate AS ReportDate, @BaseCurrency AS CurrencyName, @TotalRebate AS TotalRebate, @TotalAmount AS TotalAmount

	-- Detail
	SELECT r.ProductId, CASE	WHEN r.LicensingFeeTypeId = 13 THEN -r.ExtraAmount
								WHEN p.RebateType = 2 THEN 
								CASE WHEN (r.LicensingFee + r.ExtraAmount - r.Discount 
											- CASE WHEN @FDate >= @CutOff_RebateOnLicfee THEN ISNULL(r_37.GrossLicensingFee,0) ELSE 0 END
											- ISNULL(r.OddsBoostBonus, 0)) < 0 THEN 0 
									ELSE r.LicensingFee + r.ExtraAmount - r.Discount 
											- CASE WHEN @FDate >= @CutOff_RebateOnLicfee THEN ISNULL(r_37.GrossLicensingFee,0) ELSE 0 
											- ISNULL(r.OddsBoostBonus, 0)END 
								END 
						ELSE r.LicenseeWL END AS AmountToCompany
	FROM @Result r
		INNER JOIN @Products p ON r.ProductId = p.ProductId
		LEFT JOIN @Result_37 r_37 ON r.PartyId = r_37.PartyId AND r.ProductId = 0  AND r_37.LicensingFeeTypeId = 0 AND r.LicensingFeeTypeId = 0
END
GO