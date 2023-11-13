/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_MinFeeSettingModify]
	@PayerID				INT
	, @MinFeeSettingXML		NVARCHAR (MAX)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @MinfeeInsertedList	NVARCHAR(1000)	= ''	OUTPUT
	, @FeeTypeId			TINYINT
AS
/*
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DBCUST.bodb_Licensee
	 Notes: only update MinFee or waive month at time

	 Revisions:
		- 20150618@Florent: add column Currency to LA_Minfee
		- 20150831@Bravo: fix bug - Min fee term & Basis of billing max length.
		- 20150917@Victor: Support Chinese on Settings
		- 20170220@bruce: refactor sp [#70050]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20230331@Danny: Insert new log with more information [#FeatureID 175125]
		- 20231113@Danny: Support to remove up-coming waive period [RedmineID: #194868]

	 Params:
		+ @InvoiceSettingXML: '<MinFeeSettings>
								<MinFeeSetting>
									<MinFeeId>1</MinFeeId>
									<ProductId>1</ProductId>
									<FeeAmount>1</FeeAmount>
									<CurrencyId>1</CurrencyId>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
								</MinFeeSetting>	
								<MinFeeSetting>
									<MinFeeId>2</MinFeeId>
									<ProductId>1</ProductId>
									<FeeAmount>1</FeeAmount>
									<CurrencyId>1</CurrencyId>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
								</MinFeeSetting>
								</MinFeeSettings>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML, 
			@LogActionID INT, @LogActionIDNew INT, @LogActionIDDelete INT,
			@logSPDataNew	NVARCHAR(MAX), @logSPDataDelete NVARCHAR(MAX)
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()

	IF ISNULL(@MinFeeSettingXML, '') = '' RETURN

	DECLARE @MinFeeSetting AS TABLE (Idx INT IDENTITY(1,1), MinFeeId INT,ProductId INT, FeeAmount MONEY, CurrencyId INT, FeeTypeId INT, MinFeeTerm NVARCHAR(MAX), [Priority] SMALLINT, FromDate DATE, ToDate DATE, ActionID TINYINT DEFAULT 0)
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @MinFeeSettingXML
	
	BEGIN TRY
		INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, [Priority], FromDate, ToDate)
		SELECT MinFeeId
			, ProductId
			, FeeAmount
			, CurrencyId
			, FeeTypeId
			, MinFeeTerm
			, CASE WHEN FeeTypeId = 1/*Minfee*/THEN 1 ELSE 2/*Waive*/END AS [Priority]
			, FromDate
			, ToDate
		FROM OPENXML(@idoc, 'MinFeeSettings/MinFeeSetting')
		WITH (				
			 MinFeeId		INT				'MinFeeId'
			, ProductId		INT				'ProductId'
			, FeeAmount		MONEY			'FeeAmount'
			, CurrencyId	INT				'CurrencyId'
			, FeeTypeId		INT				'FeeTypeId'
			, MinFeeTerm	NVARCHAR(MAX)	'MinFeeTerm'
			, FromDate		DATE			'FromDate'
			, ToDate		DATE			'ToDate'
		)
	END TRY
	BEGIN CATCH
		SELECT 	@ErrMsg = 'There''s something wrong with Minfee/Waive settings, update failed. Please try again.', @ErrCode = 802
		RETURN
	END CATCH

	EXEC sp_xml_removedocument @idoc

	DECLARE @cnt INT
	SELECT @cnt = COUNT(1) FROM @MinFeeSetting

	-- fromdate must less than todate
	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FromDate > ToDate)
	BEGIN
		SELECT @ErrMsg = 'From Date could not be later than To Date', @ErrCode = 801
		RETURN
	END

	-- minfee amount must less 10,000,000,000
	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1/*minfee*/AND FeeAmount > 10000000000)
	BEGIN
		SELECT @ErrMsg = 'Minimum fee should be less than 10,000,000,000', @ErrCode = 803
		RETURN
	END

	---check case Update , compare new data with old config
	IF EXISTS (
		SELECT TOP 1 1
		FROM @MinFeeSetting a LEFT JOIN @MinFeeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId AND a.FeeTypeId = b.FeeTypeId
		WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
					OR a.ToDate BETWEEN b.FromDate AND b.ToDate
					OR b.FromDate BETWEEN a.FromDate AND a.ToDate
					OR b.ToDate BETWEEN a.FromDate AND a.ToDate
				))
	BEGIN		
		--raise error
		SELECT @ErrMsg = 'From date/To date are overlapped with the others, please try again!'
			, @ErrCode = 800
		RETURN
	END

	-- Action INSERT
	UPDATE	@MinFeeSetting
	SET		ActionID = 1
	WHERE MinFeeId = 0

	-- Action UPDATE
	UPDATE	t 
	SET	    t.ActionID = 2
	FROM	@MinFeeSetting t
	INNER JOIN dbo.LA_MinFee s WITH (NOLOCK) ON t.MinFeeId = s.MinFeeId AND t.ProductId = s.ProductId
	WHERE   ISNULL(t.FeeAmount,0) <> ISNULL(s.FeeAmount,0)
		OR t.FromDate <> s.FromDate
		OR t.ToDate <> s.ToDate
		OR ISNULL(t.MinFeeTerm,'') <> ISNULL(s.MinFeeTerm,'')
		OR t.Priority <> s.Priority
		OR ISNULL(t.CurrencyId,0) <> ISNULL(s.CurrencyId,0)

	-- 	Action DELETE
	INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, [Priority], FromDate, ToDate, ActionID)
	SELECT m.MinFeeId, m.ProductId, m.FeeAmount, m.CurrencyId, m.FeeTypeId, m.MinFeeTerm, m.[Priority], m.FromDate, m.ToDate, 3
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	LEFT JOIN @MinFeeSetting mf ON m.MinFeeId = mf.MinFeeId AND m.FeeTypeId = mf.FeeTypeId
	WHERE PartyId = @PayerID AND mf.MinFeeId IS NULL AND m.FeeTypeId = @FeeTypeId

	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE ActionID = 2) -- UPDATE
	BEGIN
		IF @FeeTypeId = 1
		BEGIN
			SELECT @logSPDataOld = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od with(nolock) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
								FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
								FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
								FORMAT(lm.FeeAmount,'N','en-us') as fa,
								e.Code AS c,
								lm.MinFeeTerm AS mt,
								lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lm.CurrencyId = e.ExchangeId
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 2) FOR JSON PATH
					) as lm
				) lm
				where op.PartyId = @PayerID  
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
			)
		END

		ELSE
		BEGIN
			SELECT @logSPDataOld = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
									FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
									FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
									lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 2)  FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    )
		END

		UPDATE	t
		SET		t.FeeAmount = s.FeeAmount
				, t.FromDate = s.FromDate
				, t.ToDate = s.ToDate
				, t.MinFeeTerm = s.MinFeeTerm
		FROM	LA_MinFee t
		INNER JOIN @MinFeeSetting s ON t.MinFeeId = s.MinFeeId
		WHERE s.ActionID = 2

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
			RETURN
		END

		
		IF @FeeTypeId = 1
		BEGIN
			SELECT @logActionID = 1301
			SELECT @logSPData = (
					SELECT	op.PartyName AS 'pi.pn' ,
							od.BrandName AS 'pi.bn',
							lm.lm AS 's'
					FROM OAS_Party op WITH(NOLOCK)
					INNER JOIN OAS_PartyDetail od with(nolock) ON od.PartyId = op.PartyID
					CROSS APPLY (
						SElECT 
						(
							SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
										FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
										FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
										FORMAT(lm.FeeAmount,'N','en-us') as fa,
										e.Code AS c,
										lm.MinFeeTerm AS mt,
										lm.MinFeeId AS FakeID
							FROM  LA_MinFee lm WITH(NOLOCK)
							LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
							INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lm.CurrencyId = e.ExchangeId
							WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  
								AND   lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 2)
							FOR JSON PATH
						) as lm
					) lm
					where op.PartyId = @PayerID  
					FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
				)
		END
		ELSE 
		BEGIN
			SELECT @logActionID = 1401
			SELECT @logSPData = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
									FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
									FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
									lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 
							AND   lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 2)
						FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES)
		END

		SELECT @endRun = GETDATE()
		SELECT @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

		-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_MinFeeSettingModify'
			,@CustId		= @PayerId
			,@Duration		= @duration
			,@TrackingValue2 = @logSPData
			,@TrackingValue =  @logSPDataOld
			,@ActionID		 = @logActionID

	END

	-- Detect logAction
	IF EXISTS ( SELECT TOP 1 1 FROM @MinFeeSetting WHERE MinFeeId > 0) 
	BEGIN
		SELECT @LogActionID = CASE WHEN EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1) THEN 1301 ELSE 1401 END
	END
	ELSE 
	BEGIN
		SELECT @LogActionID = CASE WHEN EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1) THEN 1300 ELSE 1400 END
	END

	DECLARE @MergeOutput AS TABLE (MinFeeId INT)

	-- INSERT NEW
	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE ActionID = 1)
	BEGIN
		INSERT INTO  dbo.LA_MinFee (PartyId, FeeTypeId, ProductID, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, [Priority])
		OUTPUT INSERTED.MinFeeId INTO @MergeOutput
		SELECT @PayerId PartyId, FeeTypeId, ProductID, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, [Priority]
		FROM @MinFeeSetting WHERE ActionID = 1

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
			RETURN
		END

		SELECT @MinfeeInsertedList = COALESCE(@MinfeeInsertedList + ',' + CAST(MinFeeId AS VARCHAR), CAST(MinFeeId AS VARCHAR))
		FROM @MergeOutput 

		IF @FeeTypeId = 1
		BEGIN
			SELECT @LogActionIDNew = 1300
			SELECT @logSPDataNew = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od with(nolock) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
								FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
								FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
								FORMAT(lm.FeeAmount,'N','en-us') as fa,
								e.Code AS c,
								lm.MinFeeTerm AS mt,
								lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lm.CurrencyId = e.ExchangeId
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MergeOutput x) FOR JSON PATH
					) as lm
				) lm
				where op.PartyId = @PayerID  
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
			)
		END

		ELSE
		BEGIN
			SELECT @LogActionIDNew = 1400
			SELECT @logSPDataNew = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
									FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
									FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
									lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MergeOutput x)  FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    )
		END

		SELECT @endRun = GETDATE()
		SELECT @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
		-- Log new
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_MinFeeSettingModify'
			,@CustId		= @PayerId
			,@Duration		= @duration
			,@TrackingValue2 = @logSPDataNew
			,@TrackingValue =  NULL
			,@ActionID		 = @logActionIDNew

	END

	-- DELETE
	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE ActionID = 3)
	BEGIN
		IF @FeeTypeId = 1
		BEGIN
			SELECT @LogActionIDDelete = 1302
			SELECT @logSPDataDelete = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od with(nolock) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
								FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
								FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
								FORMAT(lm.FeeAmount,'N','en-us') as fa,
								e.Code AS c,
								lm.MinFeeTerm AS mt,
								lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lm.CurrencyId = e.ExchangeId
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 3) FOR JSON PATH
					) as lm
				) lm
				where op.PartyId = @PayerID  
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
			)
		END

		ELSE
		BEGIN
			SELECT @LogActionIDDelete = 1402
			SELECT @logSPDataDelete = (
				SELECT	op.PartyName AS 'pi.pn' ,
						od.BrandName AS 'pi.bn',
						lm.lm AS 's'
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyId = op.PartyID
				CROSS APPLY (
					SElECT 
					(
						SELECT CASE WHEN lm.Productid = 0 THEN 'Sportbooks' ELSE  p.ProductName END AS pdn, 
									FORMAT (lm.FromDate,'MMM dd, yyyy')  AS fd,
									FORMAT (lm.Todate,'MMM dd, yyyy') AS td,
									lm.MinFeeId AS FakeID
						FROM  LA_MinFee lm WITH(NOLOCK)
						LEFT JOIN Product3rd p with(nolock) ON lm.ProductId = p.Productid
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 3)  FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    )
		END

		DELETE FROM LA_MinFee WITH(ROWLOCK)
		WHERE MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x WHERE x.ActionID = 3)

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 803	
			RETURN
		END

		SELECT @endRun = GETDATE()
		SELECT @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
		-- Log delete
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_MinFeeSettingModify'
			,@CustId		= @PayerId
			,@Duration		= @duration
			,@TrackingValue2 = NULL
			,@TrackingValue =  @logSPDataDelete
			,@ActionID		 = @LogActionIDDelete

	END
END
GO