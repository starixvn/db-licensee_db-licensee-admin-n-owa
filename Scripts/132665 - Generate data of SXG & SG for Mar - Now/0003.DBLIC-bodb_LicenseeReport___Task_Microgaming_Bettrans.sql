/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20200511@Parsons
	Task:   Generate data of SXG & SG for Mar - Now [#FeatureID 132665]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SXG & SG - range bettrans
*/

USE bodb_LicenseeReport
GO

DECLARE 
		@FromDate DATE = '2020-05-21', -- Current MB Date + 1
		@ToDate	DATE = '2020-05-24' -- Current Date

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE @WinlostDate <= @ToDate
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		EXEC dbo.Task_Microgaming_Bettrans @WinlossDate = @WinlostDate

		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END
END
GO