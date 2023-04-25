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
	 
	 Relation SP: Dot_Dep_CreateCurrencyLicensee
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @LogSPData	NVARCHAR(MAX),
			@Duration	INT, 
			@StartRun	DATETIME,
			@PartyID	INT, 
			@ChargeRate SMALLMONEY, 
			@DiscountGroupID INT, 
			@LicenseeID		INT,
			@ErrCode		INT = 0,			
			@ErrMsg			NVARCHAR(MAX) = ''	

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
			INSERT INTO dbo.LA_DiscountGroupCurrency(DiscountGroupId, PartyID, CurrencyId, CalculationType)
			SELECT @DiscountGroupId, @PartyID, @CurrencyId, 3 -- marked in both Currency-Count in Performance and Currency-Applied Discount

	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Insert new Currency to Discount group failed.', @ErrCode = 104
		RETURN
	END CATCH

	-- Log data
	SELECT @LogSPData = CONVERT(NVARCHAR(MAX),
		(SELECT
			@DiscountGroupId AS '@gid'
			,@PartyID AS '@pid'
			,@CurrencyId AS '@c'
			,@ChargeRate AS '@r'
			,@ErrCode AS '@ec'
			,@ErrMsg AS '@em'
			FOR XML PATH('h'), TYPE))

	-- Write log
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserId
		,@IP			= @IP
		,@LicenseeId	= 0
		,@CurrencyId	= 0
		,@SPName		= 'LA_DiscountByGrossWinCurrencyIns'
		,@CustId		= 0
		,@Duration		= @Duration
		,@Data			= @LogSPData
		,@OldData		= NULL
END
GO