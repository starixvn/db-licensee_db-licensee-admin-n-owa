/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet,Dot_Member" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE [dbo].[LA_DiscountByGrossWinCurrencyIns]
	 @SiteName				VARCHAR(10)
	,@CurrencyId			INT
	,@PT_Sportsbook			SMALLMONEY
	,@UserId				INT
	,@IP					VARCHAR(50)	

AS

/*  
	 Created: 20221103@Danny
	 DB: DBCUST.bodb_licensee
	 Task: Discount By Gross Win Add new currency
	 
	 Revisions:
		- 20221103@Danny: Initialize SP [RedmineID: #179367]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230331@Danny: Insert new log with more information [#FeatureID 175125]
		- 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
	 
	 Relation SP: Dot_Dep_CreateCurrencyLicensee
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @Duration	INT, 
			@StartRun	DATETIME,
			@PartyID	INT, 
			@ChargeRate SMALLMONEY, 
			@DiscountGroupID INT, 
			@LicenseeID		INT,
			@ErrCode		INT = 0,			
			@ErrMsg			NVARCHAR(MAX) = ''	
	DECLARE @logDiscountOld NVARCHAR(MAX), @logDiscount NVARCHAR(MAX), @logDiscountActionID INT
	SET @StartRun = GETDATE()

	SELECT @PartyID = op.PartyID,  @LicenseeID = l.LicenseeID
	FROM dbo.Licensees l WITH(NOLOCK) 
	LEFT JOIN dbo.OAS_Party op WITH(NOLOCK) ON l.LicenseeID = op.OldRefID
	WHERE l.LicenseeName = @SiteName

	SELECT @ChargeRate = 1. - (@PT_Sportsbook / 100.)

	 --LicenseeCust - check data
	IF NOT EXISTS (SELECT TOP 1 1 
				FROM dbo.LicenseeCust WITH(NOLOCK) 
				WHERE LicenseeID = @LicenseeID AND Currency = @CurrencyId)
	BEGIN
		RETURN
	END

	-- Licensee exists in LA and status is Active
	IF NOT EXISTS (	SELECT TOP 1 1 
				FROM dbo.OAS_PartyDetail WITH(NOLOCK) 
				WHERE (
						SuspendedDate IS NULL 
						AND TerminatedDate IS NULL
						)
						AND PartyID = @PartyID
				) 
	BEGIN
		RETURN
	END

	-- Licensee is in discount group
	IF NOT EXISTS (
		SELECT 1
		FROM  dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) 
			INNER JOIN dbo.LA_DiscountGroupHeader dh WITH(NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct dp WITH(NOLOCK) ON da.DiscountGroupId = dp.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupCurrency c WITH(NOLOCK) ON da.DiscountGroupId = c.DiscountGroupId AND da.PartyId = c.PartyId
		WHERE dh.FromDate <= GETDATE() AND dh.ToDate >=  GETDATE()
			AND da.PartyId = @PartyID AND dh.DiscountGroupType = 13 -- Discount group by grosswin
		)
	BEGIN
		RETURN
	END

	---- Charge rate of the new currency = charge rate of currencies which are applied discount
	--BEGIN
	--	-- charge rate of currencies which are applied discount
	--	DECLARE @CurrentChargeRate SMALLMONEY = 0

	--	SELECT TOP 1 @CurrentChargeRate = Rate
	--	FROM OAS_ChargeInfo WITH(NOLOCK)
	--	WHERE FromParty = @PartyID AND ProductID = 0 AND FromDate <= GETDATE() AND ToDate >=  GETDATE()

	--	IF @CurrentChargeRate <> @ChargeRate
	--	BEGIN
	--		SELECT @ErrMsg = 'Charge rate of the currency is different from other currencies.', @ErrCode = 103
	--		RETURN
	--	END
	--END

	BEGIN TRY
		-- Insert data
		SELECT TOP 1 @DiscountGroupId = dh.DiscountGroupId
		FROM  dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) 
			INNER JOIN dbo.LA_DiscountGroupHeader dh WITH(NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct dp WITH(NOLOCK) ON da.DiscountGroupId = dp.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupCurrency c WITH(NOLOCK) ON da.DiscountGroupId = c.DiscountGroupId AND da.PartyId = c.PartyId
		WHERE dh.FromDate <= GETDATE() AND dh.ToDate >=  GETDATE()
			AND da.PartyId = @PartyID AND dh.DiscountGroupType = 13 -- Discount group by grosswin

		IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_DiscountGroupCurrency WITH(NOLOCK) WHERE DiscountGroupId = @DiscountGroupId AND PartyID = @PartyID AND CurrencyId = @CurrencyId)
		BEGIN
			-- Log data
			SELECT @logDiscountOld = (
					SELECT ld.DiscountGroupName 'gr.gn', 
							e.Code AS  'gr.e', 
							FORMAT (ld.FromDate,'MMM dd, yyyy') 'gr.af', 
							FORMAT (ld.ToDate,'MMM dd, yyyy') 'gr.at',
							STRING_AGG(CASE WHEN ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END  ,', ') 'gr.p',
							l.l AS 'l',
							ds.s AS 'st'
					FROM LA_DiscountGroupHeader ld with(nolock) 
					INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON ld.CurrencyId = e.ExchangeId
					INNER JOIN LA_DiscountGroupProduct ldp WITH(NOLOCK) ON ld.DiscountGroupId = ldp.DiscountGroupId 
					LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid

					OUTER APPLY 
					(
						SELECT 
						(
							SELECT  PartyID AS FakeID ,PartyID AS pi,LicenseeName ln, Remark rm, 
							CASE WHEN SUM(NotCountInPert) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN CountInPer = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotCountInPert) = 0 THEN ')' ELSE ''  END  cip,
							CASE WHEN SUM(NotAppliedDiscount) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN AppliedDiscount = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotAppliedDiscount) = 0 THEN ')' ELSE '' END ap
							FROM 
								(
									SELECT  op.PartyID as PartyID ,op.PartyName AS LicenseeName, CASE WHEN lgc.CurrencyId = 142 THEN 'USDT' 
															WHEN lgc.CurrencyId IN (96, 202, 206, 208,209) THEN e.Code + ' ('+ e.currency+ ')'
															ELSE e.Code END AS Curr,
	  
											CASE WHEN lgc.CalculationType IN (1,3) THEN 1 ELSE 0 END CountInPer,
											CASE WHEN lgc.CalculationType IN (2,3) THEN 1 ELSE 0 END AppliedDiscount,
											CASE WHEN lgc.CalculationType IN (0,1)  THEN 1 ELSE 0 END NotAppliedDiscount,
											CASE WHEN lgc.CalculationType IN (0,2)  THEN 1 ELSE 0 END NotCountInPert,
											lga.Remark
									FROM LA_DiscountGroupAssignment lga WITH(NOLOCK)
									INNER JOIN OAS_Party op WITH(NOLOCK) ON lga.PartyID = op.PartyID
									INNER JOIN LA_DiscountGroupCurrency  lgc WITH(NOLOCK) ON lga.PartyID = lgc.PartyID AND lga.DiscountGroupId = lgc.DiscountGroupId
									INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON lgc.CurrencyId = e.ExchangeId
									WHERE lga.DiscountGroupId = ld.DiscountGroupId
								) x  GROUP BY PartyID,LicenseeName, Remark FOR JSON PATH
							)l
					) l
					OUTER APPLY 
					(	
						SELECT 
						(
							SELECT FORMAT(FromAmount,'N','en-us') wlf, CASE WHEN ToAmount = 10000000000000.00 THEN 'Unlimited' ELSE FORMAT(ToAmount,'N','en-us') END wlt, CAST (ChargeRateAfterDiscount * 100 AS VARCHAR(50)) + ' %' cr, ldg.DiscountGroupDetailId AS FakeID
							FROM LA_DiscountGroupDetail  ldg WITH(NOLOCK) 
							WHERE ldg.DiscountGroupId = ld.DiscountGroupId FOR JSON PATH
						) s
					) ds
					WHERE ld.DiscountGroupID = @DiscountGroupID
					GROUP BY ld.DiscountGroupName, e.Code, FORMAT (ld.FromDate,'MMM dd, yyyy'), FORMAT (ld.ToDate,'MMM dd, yyyy'), l.l, ds.s
					FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
				)
			
			INSERT INTO dbo.LA_DiscountGroupCurrency(DiscountGroupId, PartyID, CurrencyId, CalculationType)
			SELECT @DiscountGroupId, @PartyID, @CurrencyId, 3 -- marked in both Currency-Count in Performance and Currency-Applied Discount

			-- Log data
			SELECT @logDiscount = (
					SELECT ld.DiscountGroupName 'gr.gn', 
							e.Code AS  'gr.e', 
							FORMAT (ld.FromDate,'MMM dd, yyyy') 'gr.af', 
							FORMAT (ld.ToDate,'MMM dd, yyyy') 'gr.at',
							STRING_AGG(CASE WHEN ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END  ,', ') 'gr.p',
							l.l AS 'l',
							ds.s AS 'st'
					FROM LA_DiscountGroupHeader ld with(nolock) 
					INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON ld.CurrencyId = e.ExchangeId
					INNER JOIN LA_DiscountGroupProduct ldp WITH(NOLOCK) ON ld.DiscountGroupId = ldp.DiscountGroupId 
					LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid

					OUTER APPLY 
					(
						SELECT 
						(
							SELECT  PartyID AS FakeID ,PartyID AS pi,LicenseeName ln, Remark rm, 
							CASE WHEN SUM(NotCountInPert) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN CountInPer = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotCountInPert) = 0 THEN ')' ELSE ''  END  cip,
							CASE WHEN SUM(NotAppliedDiscount) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN AppliedDiscount = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotAppliedDiscount) = 0 THEN ')' ELSE '' END ap
							FROM 
								(
									SELECT  op.PartyID as PartyID ,op.PartyName AS LicenseeName, CASE WHEN lgc.CurrencyId = 142 THEN 'USDT' 
															WHEN lgc.CurrencyId IN (96, 202, 206, 208,209) THEN e.Code + ' ('+ e.currency+ ')'
															ELSE e.Code END AS Curr,
	  
											CASE WHEN lgc.CalculationType IN (1,3) THEN 1 ELSE 0 END CountInPer,
											CASE WHEN lgc.CalculationType IN (2,3) THEN 1 ELSE 0 END AppliedDiscount,
											CASE WHEN lgc.CalculationType IN (0,1)  THEN 1 ELSE 0 END NotAppliedDiscount,
											CASE WHEN lgc.CalculationType IN (0,2)  THEN 1 ELSE 0 END NotCountInPert,
											lga.Remark
									FROM LA_DiscountGroupAssignment lga WITH(NOLOCK)
									INNER JOIN OAS_Party op WITH(NOLOCK) ON lga.PartyID = op.PartyID
									INNER JOIN LA_DiscountGroupCurrency  lgc WITH(NOLOCK) ON lga.PartyID = lgc.PartyID AND lga.DiscountGroupId = lgc.DiscountGroupId
									INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON lgc.CurrencyId = e.ExchangeId
									WHERE lga.DiscountGroupId = ld.DiscountGroupId
								) x  GROUP BY PartyID,LicenseeName, Remark FOR JSON PATH
							)l
					) l
					OUTER APPLY 
					(	
						SELECT 
						(
							SELECT FORMAT(FromAmount,'N','en-us') wlf, CASE WHEN ToAmount = 10000000000000.00 THEN 'Unlimited' ELSE FORMAT(ToAmount,'N','en-us') END wlt,  CAST (ChargeRateAfterDiscount * 100 AS VARCHAR(50)) + ' %' cr, ldg.DiscountGroupDetailId AS FakeID
							FROM LA_DiscountGroupDetail  ldg WITH(NOLOCK) 
							WHERE ldg.DiscountGroupId = ld.DiscountGroupId FOR JSON PATH
						) s
					) ds
					WHERE ld.DiscountGroupID = @DiscountGroupID
					GROUP BY ld.DiscountGroupName, e.Code, FORMAT (ld.FromDate,'MMM dd, yyyy'), FORMAT (ld.ToDate,'MMM dd, yyyy'), l.l, ds.s
					FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
				)

					-- Write log
			SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

			-- Write Log Discount Setting
			EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
				@UserId			= @UserID
				,@IP			= @IP
				,@SPName		= 'LA_DiscountByGrossWinCurrencyIns'
				,@CustId		= @DiscountGroupID
				,@Duration		= @duration
				,@TrackingValue2 = @logDiscount
				,@TrackingValue = @logDiscountOld
				,@ActionID		 = 1601
		END

	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Insert new Currency to Discount group failed.', @ErrCode = 104
		RETURN
	END CATCH

	


END
GO