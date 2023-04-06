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
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML, @LogActionID INT
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()

	IF ISNULL(@MinFeeSettingXML, '') = '' RETURN

	DECLARE @MinFeeSetting AS TABLE (Idx INT IDENTITY(1,1), MinFeeId INT,ProductId INT, FeeAmount MONEY, CurrencyId INT, FeeTypeId INT, MinFeeTerm NVARCHAR(MAX), [Priority] SMALLINT, FromDate DATE, ToDate DATE, IsEdit BIT)
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @MinFeeSettingXML
	
	BEGIN TRY
		INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, [Priority], FromDate, ToDate, IsEdit)
		SELECT MinFeeId
			, ProductId
			, FeeAmount
			, CurrencyId
			, FeeTypeId
			, MinFeeTerm
			, CASE WHEN FeeTypeId = 1/*Minfee*/THEN 1 ELSE 2/*Waive*/END AS [Priority]
			, FromDate
			, ToDate
			, 1
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

	IF @cnt = 0 
		RETURN

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

	-- check time overlaping
	INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, [Priority], FromDate, ToDate, IsEdit)
	SELECT m.MinFeeId, m.ProductId, m.FeeAmount, m.CurrencyId, m.FeeTypeId, m.MinFeeTerm, m.[Priority], m.FromDate, m.ToDate, 0
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	LEFT JOIN @MinFeeSetting mf ON m.MinFeeId = mf.MinFeeId
	WHERE PartyId = @PayerID AND mf.MinFeeId IS NULL

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

	DELETE @MinFeeSetting WHERE IsEdit = 0

	-- Detect logAction
	IF EXISTS ( SELECT TOP 1 1 FROM @MinFeeSetting WHERE MinFeeId > 0) 
	BEGIN
		SELECT @LogActionID = CASE WHEN EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1) THEN 1301 ELSE 1401 END
	END
	ELSE 
	BEGIN
		SELECT @LogActionID = CASE WHEN EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1) THEN 1300 ELSE 1400 END
	END

	-- write log
	-- build old log string
	IF @LogActionID IN (1301, 1401)
	BEGIN
		IF @LogActionID = 1301
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
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =1  AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x) FOR JSON PATH
					) as lm
				) lm
				where op.PartyId = @PayerID  
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
			)
		ELSE 
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
						WHERE lm.PartyId = op.PartyID and lm.FeeTypeId =2 AND lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x)  FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    )
	END

	DECLARE @MergeOutput AS TABLE (MinFeeId INT, [$action] VARCHAR(20))

	;MERGE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) AS t
	USING @MinFeeSetting AS s ON t.MinFeeId = s.MinFeeId AND t.PartyId=@PayerID
	WHEN MATCHED THEN
		UPDATE SET t.FeeAmount = s.FeeAmount
			, t.FromDate = s.FromDate
			, t.ToDate = s.ToDate
			, t.MinFeeTerm = s.MinFeeTerm
	WHEN NOT MATCHED BY TARGET THEN
		INSERT (PartyId, FeeTypeId, ProductID, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, [Priority])
		VALUES (@PayerId, s.FeeTypeId, s.ProductID, s.FeeAmount, s.CurrencyId, s.FromDate, s.ToDate, s.MinFeeTerm, s.[Priority])
	OUTPUT INSERTED.MinFeeId, $action INTO @MergeOutput;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
		RETURN
	END

	SELECT @MinfeeInsertedList = COALESCE(@MinfeeInsertedList + ',' + CAST(MinFeeId AS VARCHAR), CAST(MinFeeId AS VARCHAR))
	FROM @MergeOutput WHERE [$action]='INSERT'

	IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting WHERE FeeTypeId = 1)
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
							AND  (lm.MinFeeId IN (SELECT  x.MinFeeId FROM @MergeOutput x)  OR lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x))
						FOR JSON PATH
					) as lm
				) lm
				where op.PartyId = @PayerID  
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES 
			)
		ELSE 
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
							AND  (lm.MinFeeId IN (SELECT  x.MinFeeId FROM @MergeOutput x)  OR lm.MinFeeId IN (SELECT x.MinFeeId FROM @MinFeeSetting x))
						FOR JSON PATH
					) AS lm
				) lm
				WHERE op.PartyId = @PayerID
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES)

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_MinFeeSettingModify'
		,@CustId		= @PayerId
		,@Duration		= @duration
		,@TrackingValue2 = @logSPData
		,@TrackingValue = @logSPDataOld
		,@ActionID		 = @logActionID
END
GO