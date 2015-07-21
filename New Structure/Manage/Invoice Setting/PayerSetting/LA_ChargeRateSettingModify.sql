USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingModify] 	
	@PayerID				INT	
	, @ChargeSettingXML		VARCHAR (MAX)
	, @ExchangeID			INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @ErrorPair			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150423@Florent
	 Task : Add/ Modify Charge rate setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
		-20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
	 Params:		
		+ @InvoiceSettingXML: '<ChargeSettings>
								  <ChargeSetting>
									<Index>1</Index>
									<ChargeId>1</ChargeId>
									<ProductId>1</ProductId>
									<FirstBilling>1</FirstBilling>
									<BasicBilling>1</BasicBilling>
									<Rate>1</Rate>
									<ChargeType>1</ChargeType>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
									<IsEdit>1</IsEdit>
								  </ChargeSetting>

								  <ChargeSetting>
									<Index>2</Index>
									<ChargeId>1</ChargeId>
									<ProductId>1</ProductId>
									<FirstBilling>1</FirstBilling>
									<BasicBilling>1</BasicBilling>
									<Rate>1</Rate>
									<ChargeType>1</ChargeType>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
									<IsEdit>1</IsEdit>
								  </ChargeSetting>
								</ChargeSettings>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_ChargeRateSettingModify'

	DECLARE @OldExchangeID INT

	--backup old data, 	
	SELECT @OldExchangeID = ISNULL(BaseCurrencyId, 0) FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE PartyID = @PayerID AND BaseCurrencyId IS NOT NULL

	IF (ISNULL(@ExchangeID, 0)  <> ISNULL(@OldExchangeID, 0))
	BEGIN
		--build log string
		SET @xml = (
				SELECT @PayerID				AS '@fp'
						, @OldExchangeID	AS '@e'				
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');

		UPDATE dbo.OAS_PartyDetail WITH( ROWLOCK, UPDLOCK)
		SET BaseCurrencyId = @ExchangeID
		WHERE PartyID = @PayerID

		SET @xml = (
				SELECT @PayerID				AS '@fp'
						, @ExchangeID		AS '@e'				
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');		
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

		--Write Log		
		BEGIN TRY
			EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
				@UserId = @UserID
				, @IP = @LoginIP
				, @LicenseeID = 0
				, @CurrencyID = 0
				, @SPName = 'LA_ChargeRateSettingModify'
				, @CustId = 0
				, @ActionId = @ActionID
				, @Duration = @duration
				, @Data = @logSPData
				, @OldData = @logSPDataOld
		END TRY
		BEGIN CATCH
			EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
				@UserID = @UserID
				, @CustID = 0
				, @ActionID = @ActionID
				, @TrackingValue = @LogSPData
				, @TrackingValue2 = @logSPDataOld
				, @duration = @duration
		END CATCH
	END

	IF ISNULL(@ChargeSettingXML, '') = ''
		RETURN
	-- parse XML
	DECLARE @ChargeSetting AS TABLE (Idx INT IDENTITY(1,1), ChargeID INT,ProductId INT, FirstBilling DATE, BasicBilling VARCHAR(125), Rate MONEY, ChargeType INT, FromDate DATE, ToDate DATE, IsEdit BIT)
	DECLARE @ChargeRate AS TABLE (ChargeID INT,ProductId INT, FromDate DATE, ToDate DATE)
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @ChargeSettingXML
	BEGIN TRY
		INSERT INTO @ChargeSetting(ChargeId, ProductId, FirstBilling, BasicBilling, Rate, ChargeType, FromDate, ToDate, IsEdit)
		SELECT ISNULL(ChargeID, 0), ProductId, FirstBilling, BasicBilling, Rate, ChargeType, FromDate, ToDate, IsEdit
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH (				
			 ChargeId		INT				'ChargeId'
			, ProductId		INT				'ProductId'
			, FirstBilling	DATE			'FirstBilling'
			, BasicBilling	VARCHAR(125)	'BasicBilling'
			, Rate			MONEY			'Rate'
			, ChargeType	INT				'ChargeType'
			, FromDate		DATE			'FromDate'
			, ToDate		DATE			'ToDate'
			, IsEdit		BIT				'IsEdit' 
		)
	END TRY
	BEGIN CATCH 
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701	
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc
	-- check  0 < rate < 1
	IF EXISTS (SELECT 1 FROM @ChargeSetting WHERE Rate < 0 OR Rate > 1)
	BEGIN
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701	
		RETURN
	END
	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')
	
	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2

	-- check overlap time charge
	INSERT INTO @ChargeSetting(ChargeId, ProductId, FirstBilling, BasicBilling, Rate, ChargeType, FromDate, ToDate)
	SELECT a.ChargeId, a.ProductId, b.FirstOfBilling, b.BasicOfBilling, Rate, ChargeType, a.FromDate, a.ToDate
	FROM dbo.LA_f_ChargeInfo(@PayerID, @MinDate, @MaxDate ,@ProductListAll, 'OA', 1) a	
		INNER JOIN dbo.OAS_ChargeInfo b WITH (NOLOCK) ON a.ChargeID = b.ChargeID
	WHERE a.ChargeID NOT IN (SELECT ChargeID FROM @ChargeSetting)	
	
	---check case Update , compare new data with old config 
	IF NOT EXISTS (
			SELECT TOP 1 1
			FROM @ChargeSetting a LEFT JOIN @ChargeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId 
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate
					))
	BEGIN
		-- case Update
			IF EXISTS (SELECT TOP 1 1 FROM @ChargeSetting cs WHERE IsEdit = 1)
			BEGIN
				-- write log
				--build log string
				SET @xml = (
						SELECT	ci.ChargeId				AS '@c'
								, ci.FromParty			AS '@fp'  
								, ci.ProductId			AS '@tp'
								, ci.FirstOfBilling		AS '@fb'
								, ci.BasicOfBilling		AS '@bb'
								, ci.Rate				AS '@r'
								, ci.ChargeType			AS '@ct'
								, ci.FromDate			AS '@fd'
								, ci.ToDate				AS '@td'								
						FROM @ChargeSetting  cs
							INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID AND cs.IsEdit = 1
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');

				;MERGE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) AS t
				USING (SELECT ChargeID, FirstBilling, BasicBilling, Rate, FromDate, ToDate FROM @ChargeSetting WHERE IsEdit = 1) AS s
				ON (t.ChargeID = s.ChargeID)
				WHEN MATCHED
					THEN UPDATE SET t.FirstOfBilling = s.FirstBilling
								, t.BasicOfBilling = s.BasicBilling
								, t.Rate = s.Rate
								, t.FromDate = s.FromDate
								, t.ToDate = s.ToDate;										
				
				IF @@ERROR <> 0
				BEGIN
					SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701	
					RETURN
				END
					
				SET @xml = (
						SELECT	ci.ChargeId				AS '@c'
								, ci.FromParty			AS '@fp'  
								, cs.ProductId			AS '@tp'
								, cs.FirstBilling		AS '@fb'
								, cs.BasicBilling		AS '@bb'
								, cs.Rate				AS '@r'
								, cs.ChargeType			AS '@ct'
								, cs.FromDate			AS '@fd'
								, cs.ToDate				AS '@td'
								, @ExchangeID			AS '@e'
						FROM @ChargeSetting  cs
							INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID AND cs.IsEdit = 1
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SET @endRun = GETDATE()
				SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

				--Write Log		
				BEGIN TRY
					EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
						@UserId = @UserID
						, @IP = @LoginIP
						, @LicenseeID = 0
						, @CurrencyID = 0
						, @SPName = 'LA_ChargeRateSettingModify'
						, @CustId = 0
						, @ActionId = @ActionID
						, @Duration = @duration
						, @Data = @logSPData
						, @OldData = @logSPDataOld
				END TRY
				BEGIN CATCH
					EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
						@UserID = @UserID
						, @CustID = 0
						, @ActionID = @ActionID
						, @TrackingValue = @LogSPData
						, @TrackingValue2 = @logSPDataOld
						, @duration = @duration
				END CATCH
			END
			-- Case Insert			
			IF EXISTS (SELECT TOP 1 1 FROM @ChargeSetting cs WHERE IsEdit = 0)
			BEGIN 

				DECLARE @ToParty INT, @ParentChargeID INT, @Remark VARCHAR(200) = ''

				SELECT @ToParty = c.ToParty
					, @ParentChargeID = c.ParentChargeID
				FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
					INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID
						AND cs.SystemID = 2
				WHERE FromParty = @PayerID
					AND c.FromDate = (
						SELECT MAX(c.FromDate)
						FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
						INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID
							AND cs.SystemID = 2
						WHERE FromParty = @PayerID
						)
										
				SET @Remark = @Remark + 'created date: ' + CONVERT(VARCHAR(20), GETDATE(), 101)
				
				DECLARE @ChargeID AS TABLE (ChargeID INT)
					
				INSERT INTO dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK)(ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, FirstOfBilling, BasicOfBilling)
				OUTPUT INSERTED.ChargeID
				INTO @ChargeID
				SELECT ProductId, @PayerID, @ToParty, @ParentChargeID, Rate, ChargeType, FromDate, ToDate, @Remark, FirstBilling, BasicBilling
				FROM @ChargeSetting					
				WHERE ChargeID = 0 
					AND IsEdit = 0
											
				IF @@ERROR <> 0
				BEGIN
					SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701	
					RETURN
				END
							
				IF ISNULL(@ParentChargeID, 0) = 1				
				BEGIN
					INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
					SELECT ChargeID, 2
					FROM @ChargeID
					UNION 
					SELECT ChargeID, 4
					FROM @ChargeID
				END
				ELSE 
				BEGIN 
					INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
					SELECT ChargeID, 2
					FROM @ChargeID
				END

				IF @@ERROR <> 0
				BEGIN
					--rolback
					DELETE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) 
					WHERE ChargeID IN (SELECT ChargeID FROM @ChargeID) 		
											
					SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701	
					RETURN
				END	
					
				SET @xml = (
						SELECT	ci.ChargeId				AS '@c'
								, ci.FromParty			AS '@fp'  
								, ci.ProductId			AS '@tp'
								, ci.FirstOfBilling		AS '@fb'
								, ci.BasicOfBilling		AS '@bb'
								, ci.Rate				AS '@r'
								, ci.ChargeType			AS '@ct'
								, ci.FromDate			AS '@fd'
								, ci.ToDate				AS '@td'
						FROM @ChargeID cs
							INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SET @endRun = GETDATE()
				SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
				SET @logSPDataOld = NULL
				--Write Log		
				BEGIN TRY
					EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
						@UserId = @UserID
						, @IP = @LoginIP
						, @LicenseeID = 0
						, @CurrencyID = 0
						, @SPName = 'LA_ChargeRateSettingModify'
						, @CustId = 0
						, @ActionId = @ActionID
						, @Duration = @duration
						, @Data = @logSPData
						, @OldData = @logSPDataOld
				END TRY
				BEGIN CATCH
					EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
						@UserID = @UserID
						, @CustID = 0
						, @ActionID = @ActionID
						, @TrackingValue = @LogSPData
						, @TrackingValue2 = @logSPDataOld
						, @duration = @duration
				END CATCH
			END
	END
	ELSE
	BEGIN
		SELECT @ErrorPair = COALESCE(@ErrorPair + ',' + '( ' +CAST(a.Idx AS VARCHAR)+','+ CAST(b.Idx AS VARCHAR) +' )', '( ' +CAST(a.Idx AS VARCHAR)+', '+ CAST(b.Idx AS VARCHAR) +' )')
		FROM @ChargeSetting a LEFT JOIN @ChargeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId 
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate)
		SET @ErrorPair = SUBSTRING(@ErrorPair, 0, LEN(@ErrorPair)/2 +1)
		--raise error
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date'
			, @ErrCode = 700
		RETURN		
	END
	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_ChargeRateSettingModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_ChargeRateSettingModify] TO bodbAdminNet