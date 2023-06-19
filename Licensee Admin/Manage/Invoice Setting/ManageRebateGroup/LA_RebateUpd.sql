/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateUpd] 
	@GroupId			SMALLINT = 0,
	@GroupName			NVARCHAR(50),
	@FromDate			DATE,
	@ToDate				DATE,
	@ProductIds			VARCHAR(512) = '',
	@PartyIds			VARCHAR(4000) = '',
	@Rate				DECIMAL(9, 8),
	@RebateGroupType	TINYINT,
	@UserId				INT,
	@Remark				NVARCHAR(4000) = '',
	@LoginIp			VARCHAR (50)	= '',
	@ErrCode			INT = 0 OUTPUT,
	@ErrMsg				VARCHAR(4000)= '' OUTPUT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Update rebate group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220210@Percy: Add param @RebateGroupType to offer Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20230417@Danny: Insert new log with more information [#FeatureID 175125]
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), 
			@logSPDataOld	NVARCHAR(MAX), @actionID INT = 1701

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType IN (2, 12, 22) AND DiscountGroupId <> @GroupId)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END
		
	INSERT INTO @Payers(PayerId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- check exists setting
	BEGIN
		SELECT @ErrMsg = ''

		SELECT @ErrMsg = MAX (CASE
								WHEN @RebateGroupType = 12 AND h.DiscountGroupType = 12 THEN 'Licensee is in another Tier Rebate group.'
								WHEN @RebateGroupType = 2 AND h.DiscountGroupType = 22 THEN 'Licensee is in another Rebate on Lic WL group.'
								WHEN @RebateGroupType = 22 AND h.DiscountGroupType = 2 THEN 'Licensee is in another Rebate on Lic Fee group.'
								WHEN @RebateGroupType IN (2, 22) AND h.DiscountGroupType = @RebateGroupType AND pt.ProductId IS NOT NULL THEN 'Duplicated product with current group.'
								ELSE '' END)
		FROM @Payers t
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON t.PayerId = a.PartyId
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
			LEFT JOIN @Products pt ON pt.ProductId = p.ProductId
		WHERE h.DiscountGroupType IN (2, 12, 22)
			AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
			AND h.DiscountGroupId <> @GroupId

		IF @ErrMsg <> ''
		BEGIN
			SELECT @ErrCode = 503
			RETURN
		END
	END

	-- if group is tier rebate, check base currency all payers
	DECLARE @BaseCurrency TABLE (BaseCurrencyId INT)
	DECLARE @BaseCurrencyId INT = 0

	IF @RebateGroupType = 12
	BEGIN
		INSERT INTO @BaseCurrency (BaseCurrencyId)
		SELECT DISTINCT BaseCurrencyId
		FROM @Payers p
			INNER JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PayerId = bc.PartyId
		WHERE bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

		IF @@ROWCOUNT <> 1
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Licensees billing currency must be the same.'
			RETURN
		END

		SELECT @BaseCurrencyId = BaseCurrencyId FROM @BaseCurrency
	END

	-- #Region Update 
	IF ISNULL(@GroupId, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--get old data for write log
	SELECT @logSPDataOld = (
		SELECT  ld.DiscountGroupName 'gs.gn', 
				FORMAT (ld.FromDate,'MMM dd, yyyy') 'gs.af', 
				FORMAT (ld.ToDate,'MMM dd, yyyy') 'gs.at',
				CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' 'gs.r' ,
				CASE WHEN ld.DiscountGroupType = 2 THEN 'Rebate on Licensing Fee'
					 WHEN ld.DiscountGroupType = 12 THEN 'Tier Rebate'
					 WHEN ld.DiscountGroupType = 22 THEN 'Rebate on Licensing WL'
				END 'gs.rt',
				ld.Remark 'gs.rm',
				pig.val AS 'gs.pig',
				pig.pid AS 'gs.pid',
				pa.val AS 'gs.pa'
		FROM LA_DiscountGroupHeader ld WITH(NOLOCK) 
		INNER JOIN LA_DiscountGroupDetail ldg WITH(NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
		CROSS APPLY (
			SELECT  STRING_AGG(op.PartyName,', ') AS val, STRING_AGG(CAST(lda.PartyID AS VARCHAR(50)),',') AS pid
			FROM	LA_DiscountGroupAssignment lda
			INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lda.PartyID = op.PartyID
			WHERE ld.DiscountGroupId = lda.DiscountGroupId
		) pig
		CROSS APPLY 
		(
			SELECT STRING_AGG(CASE WHEN  ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END,', ') AS val
			FROM  LA_DiscountGroupProduct ldp WITH(NOLOCK)
			LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid
			WHERE ld.DiscountGroupId = ldp.DiscountGroupId
		) pa
		WHERE ld.DiscountGroupId = @GroupId
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	--update rebate group assingment
	;MERGE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK) AS t
	USING @Payers AS s
	ON (t.DiscountGroupId = @GroupId AND t.PartyId = s.PayerId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, PartyId, IsApplyDiscount)
				VALUES(@GroupId, s.PayerId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group product
	;MERGE dbo.LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK) AS t
	USING @Products AS s
	ON (t.DiscountGroupId = @GroupId AND t.ProductId = s.ProductId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, ProductId, CalculationType)
				VALUES(@GroupId, s.ProductId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group detail
	UPDATE dbo.LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK)
	SET Rate = @Rate
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group header
	UPDATE dbo.LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
	SET DiscountGroupName = @GroupName
		, FromDate = @FromDate
		, ToDate = @ToDate
		, Remark = @Remark
		, ModifiedDate = GETDATE()
		, DiscountGroupType = @RebateGroupType
		, CurrencyId = @BaseCurrencyId
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	-- #Endregion Update 

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SELECT @logSPData = (
		SELECT  ld.DiscountGroupName 'gs.gn', 
				FORMAT (ld.FromDate,'MMM dd, yyyy') 'gs.af', 
				FORMAT (ld.ToDate,'MMM dd, yyyy') 'gs.at',
				CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' 'gs.r' ,
				CASE WHEN ld.DiscountGroupType = 2 THEN 'Rebate on Licensing Fee'
					 WHEN ld.DiscountGroupType = 12 THEN 'Tier Rebate'
					 WHEN ld.DiscountGroupType = 22 THEN 'Rebate on Licensing WL'
				END 'gs.rt',
				ld.Remark 'gs.rm',
				pig.val AS 'gs.pig',
				pig.pid AS 'gs.pid',
				pa.val AS 'gs.pa'
		FROM LA_DiscountGroupHeader ld WITH(NOLOCK) 
		INNER JOIN LA_DiscountGroupDetail ldg WITH(NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
		CROSS APPLY (
			SELECT  STRING_AGG(op.PartyName,', ') AS val, STRING_AGG(CAST(lda.PartyID AS VARCHAR(50)),',') AS pid
			FROM	LA_DiscountGroupAssignment lda
			INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lda.PartyID = op.PartyID
			WHERE ld.DiscountGroupId = lda.DiscountGroupId
		) pig
		CROSS APPLY 
		(
			SELECT STRING_AGG(CASE WHEN  ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END,', ') AS val
			FROM  LA_DiscountGroupProduct ldp WITH(NOLOCK)
			LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid
			WHERE ld.DiscountGroupId = ldp.DiscountGroupId
		) pa
		WHERE ld.DiscountGroupId = @GroupId
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_RebateUpd'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO
