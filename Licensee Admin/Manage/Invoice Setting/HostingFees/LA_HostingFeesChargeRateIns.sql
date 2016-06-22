USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesChargeRateIns]
	@PayerId			INT,	
	@BaseCurrencyId		INT	,	
	@XmlChargeRates		NVARCHAR(MAX),
	@XmlWaives			NVARCHAR(MAX),
	@UserID				INT,
	@LoginIP			VARCHAR (50)	= '',
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160620@Bravo
	 Task : Insert hosting fees charge rate settings
	 DB: DB052.bodb_Licensee  
   
	 Revisions:
	 Params:
		+ @XmlChargeRates: '<ChargeRates>
								<ChargeRate>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<FirstBilling></FirstBilling>
									<BasisOfBilling></BasisOfBilling>
									<HostingFeesId></HostingFeesId>		
								</ChargeRate>
								<ChargeRate>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<FirstBilling></FirstBilling>
									<BasisOfBilling></BasisOfBilling>
									<HostingFeesId></HostingFeesId>		
								</ChargeRate>
							</ChargeRates>
		+ @@XmlWaives:
							<Waives>
								<Waive>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<BasedMinimunFees></BasedMinimunFees>		
								</Waive>
								<Waive>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<BasedMinimunFees></BasedMinimunFees>		
								</Waive>
							</Waives>'
	 Example:
		EXEC dbo.LA_HostingFeesSel 0
*/
BEGIN
	SET NOCOUNT ON

	-- Region: Insert hosting fees details
	SELECT @XmlChargeRates = REPLACE(@XmlChargeRates,N'&',N'&amp;')
	SELECT @XmlWaives = REPLACE(@XmlWaives,N'&',N'&amp;')

	DECLARE @ChargeRates AS TABLE (
		ChargeId		INT	,
		FromDate		DATETIME,
		ToDate			DATETIME,
		FirstBilling	DATETIME,
		BasisOfBilling	NVARCHAR(200),
		HostingFeesId	INT)
	DECLARE @Waives AS TABLE (
		ChargeId		INT	,
		FromDate		DATETIME,
		ToDate			DATETIME,
		BasedMinimunFees INT)
			
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @XmlChargeRates

	DECLARE @idoc1 AS INT
	EXEC sp_xml_preparedocument @idoc1 OUTPUT, @XmlWaives

	BEGIN TRY
		INSERT INTO @ChargeRates(ChargeId, FromDate, ToDate, FirstBilling, BasisOfBilling, HostingFeesId)
		SELECT ChargeId, FromDate, ToDate, FirstBilling, BasisOfBilling, HostingFeesId
		FROM OPENXML(@idoc, 'ChargeRates/ChargeRate')
		WITH (
			ChargeId		INT				'ChargeId',
			FromDate		DATETIME		'FromDate',	
			ToDate			DATETIME		'ToDate',
			FirstBilling	DATETIME		'FirstBilling',
			BasisOfBilling	NVARCHAR(200)	'BasisOfBilling',
			HostingFeesId	INT				'HostingFeesId'
		)

		INSERT INTO @Waives(ChargeId, FromDate, ToDate, BasedMinimunFees)
		SELECT ChargeId, FromDate, ToDate, BasedMinimunFees
		FROM OPENXML(@idoc1, 'Waives/Waive')
		WITH (
			ChargeId		INT				'ChargeId',
			FromDate		DATETIME		'FromDate',	
			ToDate			DATETIME		'ToDate',
			BasedMinimunFees INT			'BasedMinimunFees'
		)

		-- Update charge rate
		IF EXISTS (	SELECT 1 
					FROM @ChargeRates c1 INNER JOIN @ChargeRates c2 
						ON c1.ChargeId > 0 
						AND c2.ChargeId > 0 
						AND c1.ChargeId != c2.ChargeId 
						AND ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate)) )
			OR EXISTS ( SELECT 1 
					FROM @ChargeRates c1 INNER JOIN dbo.LA_HostingFeesSetting c2
						ON ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate))
					WHERE c2.FromParty = @PayerId AND c2.SettingType = 1 AND c1.ChargeId != 0 AND c2.ChargeId NOT IN (SELECT ChargeId FROM @ChargeRates WHERE c1.ChargeId != 0)
			)			
		BEGIN
			SELECT 	@ErrMsg = 'Invalid date range of charge rate. Please try again.', @ErrCode = 11
			RETURN
		END
		ELSE
		BEGIN 
			UPDATE h
			SET h.FromDate = c.FromDate, h.ToDate = c.ToDate, h.FirstBilling = c.FirstBilling, h.BasisOfBilling = c.BasisOfBilling, h.HostingFeesId = c.HostingFeesId
			FROM dbo.LA_HostingFeesSetting h INNER JOIN @ChargeRates c ON h.ChargeId = c.ChargeId
			WHERE h.SettingType = 1 -- charge rate
				AND c.ChargeId > 0
		END

		-- Insert new charge rate
		IF EXISTS ( SELECT 1 
					FROM @ChargeRates c1 INNER JOIN dbo.LA_HostingFeesSetting c2
						ON ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate))
					WHERE c2.FromParty = @PayerId AND c2.SettingType = 1 AND c1.ChargeId = 0
			)
		BEGIN
			SELECT 	@ErrMsg = 'Invalid date range of charge rate. Please try again.', @ErrCode = 12
			RETURN
		END
		ELSE
		BEGIN 
			INSERT INTO LA_HostingFeesSetting(SettingType,ParentId,FromParty,ToParty,FromDate,ToDate,ProductName,FirstBilling,BasisOfBilling,BaseCurrencyId,HostingFeesId,Remark)
			SELECT 1, 0, @PayerId, 1, c.FromDate, c.ToDate, 'Hosting', c.FirstBilling, c.BasisOfBilling, @BaseCurrencyId, c.HostingFeesId, 'Insert new hosting fees charge rate.'
			FROM @ChargeRates c
			WHERE c.ChargeId = 0
		END

		-- Update waive
		IF EXISTS (	SELECT 1 
					FROM @Waives c1 INNER JOIN @Waives c2 
						ON c1.ChargeId > 0 
						AND c2.ChargeId > 0 
						AND c1.ChargeId != c2.ChargeId 
						AND ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate)) )
			OR EXISTS ( SELECT 1 
					FROM @Waives c1 INNER JOIN dbo.LA_HostingFeesSetting c2
						ON ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate))
					WHERE c2.FromParty = @PayerId AND c2.SettingType = 2 AND c1.ChargeId != 0 AND c2.ChargeId NOT IN (SELECT ChargeId FROM @Waives WHERE c1.ChargeId != 0)
			)				
		BEGIN
			SELECT 	@ErrMsg = 'Invalid date range of waive. Please try again.', @ErrCode = 13
			RETURN
		END
		ELSE
		BEGIN			
			UPDATE h
			SET h.FromDate = c.FromDate, h.ToDate = c.ToDate, h.BasedMinimunFees = c.BasedMinimunFees
			FROM dbo.LA_HostingFeesSetting h INNER JOIN @Waives c ON h.ChargeId = c.ChargeId
			WHERE h.SettingType = 2 -- waive
				AND c.ChargeId > 0
		END

		-- Insert new waive
		IF EXISTS ( SELECT 1 
					FROM @Waives c1 INNER JOIN dbo.LA_HostingFeesSetting c2
						ON ((c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR (c1.ToDate BETWEEN c2.FromDate AND c2.ToDate))
					WHERE c2.FromParty = @PayerId AND c2.SettingType = 2 AND c1.ChargeId = 0
			)
		BEGIN
			SELECT 	@ErrMsg = 'Invalid date range of waive. Please try again.', @ErrCode = 14
			RETURN
		END
		ELSE
		BEGIN
			INSERT INTO LA_HostingFeesSetting(SettingType,ParentId,FromParty,ToParty,FromDate,ToDate,ProductName,BaseCurrencyId,Remark)
			SELECT 2, 0, @PayerId, 1, c.FromDate, c.ToDate, 'Hosting', @BaseCurrencyId, 'Insert new hosting fees waive.'
			FROM @Waives c
			WHERE c.ChargeId = 0
		END		

	END TRY
	BEGIN CATCH 
		-- Rollback
		
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 1	
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc	

	-- EndRegion
	
	-- Region: Write Log

	-- EndRegion
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesChargeRateIns] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesChargeRateIns] TO bodbAdminNet 

